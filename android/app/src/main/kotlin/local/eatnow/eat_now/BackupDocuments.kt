package local.eatwhat.campus

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** SAF streams backups directly; Binder carries only a URI or path. */
class BackupDocuments(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private val directory get() = File(activity.cacheDir, "backup-transfer")
    private var pending: MethodChannel.Result? = null
    private var exporting: File? = null
    private var limit = MAX_BYTES
    private var closed = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed || pending != null) {
            result.error("BACKUP_BUSY", "Backup transfer is busy", null)
            return
        }
        try {
            check(directory.exists() || directory.mkdirs())
            when (call.method) {
                "prepareExport" -> result.success(File.createTempFile("out-", ".json", directory).absolutePath)
                "saveFile" -> {
                    val file = File(call.argument<String>("path") ?: "").canonicalFile
                    check(file.parentFile == directory.canonicalFile && file.isFile && file.length() <= MAX_BYTES)
                    val name = call.argument<String>("name") ?: "eaten-yet-backup.json"
                    check(name.length <= 100 && !name.contains('/') && !name.contains('\\'))
                    exporting = file
                    pending = result
                    activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, name)
                    }, SAVE)
                }
                "openFile" -> {
                    val requested = call.argument<Number>("maxBytes")?.toLong() ?: MAX_BYTES
                    check(requested in 1..MAX_BYTES)
                    limit = requested
                    pending = result
                    activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }, OPEN)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            pending = null
            exporting?.delete()
            exporting = null
            result.error("BACKUP", "Cannot open backup file picker", null)
        }
    }

    fun onActivityResult(request: Int, resultCode: Int, data: Intent?): Boolean {
        if (request != SAVE && request != OPEN) return false
        val result = pending ?: return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            exporting?.delete()
            exporting = null
            pending = null
            result.success(if (request == SAVE) false else null)
            return true
        }
        val source = exporting
        val maxSize = limit
        executor.execute {
            var imported: File? = null
            try {
                if (request == SAVE) {
                    check(source != null && source.isFile && source.length() <= MAX_BYTES)
                    activity.contentResolver.openOutputStream(uri, "wt").use { output ->
                        check(output != null)
                        source.inputStream().use { input -> input.copyTo(output, 65536) }
                    }
                } else {
                    imported = File.createTempFile("in-", ".json", directory)
                    activity.contentResolver.openInputStream(uri).use { input ->
                        check(input != null)
                        imported!!.outputStream().use { output ->
                            val buffer = ByteArray(65536)
                            var total = 0L
                            while (true) {
                                val read = input.read(buffer)
                                if (read < 0) break
                                total += read
                                check(total <= maxSize) { "Backup file is too large" }
                                output.write(buffer, 0, read)
                            }
                        }
                    }
                }
                val path = imported?.absolutePath
                activity.runOnUiThread {
                    exporting = null
                    if (!closed) { pending = null; result.success(if (request == SAVE) true else path) }
                    else imported?.delete()
                }
            } catch (error: Exception) {
                imported?.delete()
                activity.runOnUiThread {
                    exporting = null
                    if (!closed) { pending = null; result.error("BACKUP", "Backup file transfer failed", null) }
                }
            } finally {
                source?.delete()
            }
        }
        return true
    }

    fun close() {
        closed = true
        pending?.error("BACKUP", "Backup transfer interrupted", null)
        pending = null
        exporting?.delete()
        exporting = null
        executor.shutdown()
    }

    companion object {
        private const val SAVE = 4101
        private const val OPEN = 4102
        private const val MAX_BYTES = 64L * 1024 * 1024
    }
}
