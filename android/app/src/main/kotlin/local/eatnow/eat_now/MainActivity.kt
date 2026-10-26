package local.eatwhat.campus

import android.content.Intent
import android.content.ClipData
import android.content.pm.PackageManager
import android.content.pm.PackageInfo
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val verifier = Executors.newSingleThreadExecutor()
    private val updateDir get() = File(cacheDir, "updates")
    private val apk get() = File(updateDir, "update.apk")
    private var verifiedHash: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "local.eatwhat.campus/update")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                        "prepare" -> {
                            verifiedHash = null
                            check(updateDir.exists() || updateDir.mkdirs()) { "无法创建下载目录" }
                            check(!apk.exists() || apk.delete()) { "无法清理旧安装包" }
                            result.success(apk.absolutePath)
                        }
                        "verify" -> {
                            val hash = call.argument<String>("sha256") ?: ""
                            val size = call.argument<Number>("size")?.toLong() ?: 0
                            verifiedHash = null
                            verifier.execute {
                                try {
                                    check(hash.matches(Regex("[0-9a-f]{64}"))) { "缺少安装包校验值" }
                                    check(apk.length() == size && size > 0) { "安装包大小不匹配" }
                                    check(hashFile() == hash) { "安装包校验失败，请重新下载" }
                                    validatePackage()
                                    runOnUiThread { verifiedHash = hash; result.success(null) }
                                } catch (e: Exception) {
                                    apk.delete()
                                    runOnUiThread { result.error("VERIFY", e.message, null) }
                                }
                            }
                        }
                        "install" -> {
                            val hash = verifiedHash
                            check(hash != null && apk.exists()) { "请先下载并校验安装包" }
                            if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")))
                                result.success("permission")
                            } else {
                                // Recheck before exposing the private cached file to the system installer.
                                verifier.execute {
                                    try {
                                        check(hashFile() == hash) { "安装包已改变，请重新下载" }
                                        validatePackage()
                                        runOnUiThread {
                                            try {
                                                val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
                                                startActivity(Intent(Intent.ACTION_VIEW).apply {
                                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                                    clipData = ClipData.newRawUri("update", uri)
                                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                                })
                                                result.success("opened")
                                            } catch (e: Exception) { result.error("INSTALL", "无法打开系统安装界面", null) }
                                        }
                                    } catch (e: Exception) {
                                        runOnUiThread { verifiedHash = null; result.error("VERIFY", e.message, null) }
                                    }
                                }
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) { result.error("UPDATE", e.message, null) }
            }
    }

    private fun hashFile(): String {
        val digest = MessageDigest.getInstance("SHA-256")
        apk.inputStream().use { stream ->
            val buffer = ByteArray(65536)
            while (true) { val n = stream.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    @Suppress("DEPRECATION")
    private fun validatePackage() {
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val candidate = packageManager.getPackageArchiveInfo(apk.absolutePath, flags)
            ?: error("安装包无法解析")
        val installed = packageManager.getPackageInfo(packageName, flags)
        check(candidate.packageName == packageName) { "安装包不属于吃了么" }
        val nextCode = if (Build.VERSION.SDK_INT >= 28) candidate.longVersionCode else candidate.versionCode.toLong()
        val currentCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
        check(nextCode > currentCode) { "安装包版本不高于当前版本" }
        fun signatures(info: PackageInfo): Set<String> {
            val sigs = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
            return sigs?.map { it.toCharsString() }?.toSet() ?: emptySet()
        }
        val current = signatures(installed)
        check(current.isNotEmpty() && signatures(candidate) == current) { "安装包签名不同，无法安全覆盖升级" }
    }
}
