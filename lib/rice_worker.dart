import 'dart:convert';
import 'dart:math';
import 'rice.dart';

// Only snapshots cross the isolate boundary; no storage or widget state.
RiceResult calculateRice(Map<String, dynamic> job) {
  final plan = RicePlan.fromJson(job['plan']);
  final prefs = job['preferences'] as Map<String, dynamic>?;
  final dishCounts = Map<String,int>.from(prefs?['dishes'] ?? {});
  final pairCounts = Map<String,int>.from(prefs?['pairs'] ?? {});
  final dishLogs = <String,double>{};
  final pairLogs = <String,double>{};
  double score(List<String> names) {
    final keys = <String>{for (final name in names) jsonEncode(['rice',plan.storeKey,plan.location,name]),
      if (job['snack'] != null) job['snack'] as String}.toList();
    var dishes = 0.0, pairs = 0.0, count = 0;
    for (var i=0;i<keys.length;i++) {
      dishes += dishLogs.putIfAbsent(keys[i], () => log(1 + min(2.0,(dishCounts[keys[i]] ?? 0)*.25)));
      for (var j=i+1;j<keys.length;j++) {
        final key=jsonEncode([keys[i],keys[j]]..sort());
        pairs += pairLogs.putIfAbsent(key, () => log(1 + min(1.0,(pairCounts[key] ?? 0)*.15)));
        count++;
      }
    }
    return exp(dishes/keys.length + (count == 0 ? 0 : pairs/count));
  }
  return randomRice(plan,job['budget'],List<String?>.from(job['dishes']),
    Set<int>.from(job['locked']),Random(job['seed']),freeSelection:job['free'],
    meatCount:job['meatCount'],quantities:List<int>.from(job['quantities']),
    baseQuantity:job['baseQuantity'],score:prefs?['enabled'] == true ? score : null);
}
