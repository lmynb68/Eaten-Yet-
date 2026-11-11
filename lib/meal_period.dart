import 'dart:convert';
import 'language.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const mealPeriodKey = 'eat_what.meal_period';
const periodNames = {'breakfast':'早餐','lunch':'午餐','dinner':'晚餐'};
class MealSchedule {
  final int breakfast, lunch, dinner;
  const MealSchedule({this.breakfast=300,this.lunch=600,this.dinner=960});
  bool get valid => breakfast>=0 && breakfast<lunch && lunch<dinner && dinner<1440;
  List<int> get starts => [breakfast,lunch,dinner];
  String label(int minutes) => '${(minutes~/60).toString().padLeft(2,'0')}:${(minutes%60).toString().padLeft(2,'0')}';
}
String clockPeriod(DateTime now, [MealSchedule schedule=const MealSchedule()]) {
  if(!schedule.valid) schedule=const MealSchedule();
  final minutes=now.hour*60+now.minute;
  return minutes>=schedule.breakfast && minutes<schedule.lunch ? 'breakfast' : minutes>=schedule.lunch && minutes<schedule.dinner ? 'lunch' : 'dinner';
}
Map<String,dynamic> _readMealConfig(SharedPreferences prefs) {
  try {
    // Old or damaged preferences can have another supported storage type.
    // Keep the saved value until the user confirms a replacement in settings.
    final saved=prefs.get(mealPeriodKey);
    if(saved is! String) return {};
    if(['auto',...periodNames.keys].contains(saved)) return {'mode':saved};
    final value=jsonDecode(saved);
    return value is Map<String,dynamic>?value:{};
  } catch(_) {return {};}
}
String readMealChoice(SharedPreferences prefs) {
  final value=_readMealConfig(prefs)['mode'];
  return value=='auto' || periodNames.containsKey(value) ? value as String : 'auto';
}
bool hasMealChoice(SharedPreferences prefs) => ['auto',...periodNames.keys].contains(_readMealConfig(prefs)['mode']);
MealSchedule readMealSchedule(SharedPreferences prefs) {
  final config=_readMealConfig(prefs);
  if(config['breakfast'] is! int || config['lunch'] is! int || config['dinner'] is! int) return const MealSchedule();
  final schedule=MealSchedule(breakfast:config['breakfast'],lunch:config['lunch'],dinner:config['dinner']);
  return schedule.valid?schedule:const MealSchedule();
}
Future<void> saveMealConfig(SharedPreferences prefs,String mode,MealSchedule schedule) async {
  if(!schedule.valid || !['auto',...periodNames.keys].contains(mode)) throw ArgumentError('餐次设置无效');
  // One persisted value avoids saving a mode without its matching schedule.
  if(!await prefs.setString(mealPeriodKey,jsonEncode({'mode':mode,'breakfast':schedule.breakfast,'lunch':schedule.lunch,'dinner':schedule.dinner}))) throw StateError('保存失败');
}
Future<String?> showMealChoice(BuildContext context, SharedPreferences prefs, {bool first=false}) => showDialog<String>(
  context:context, barrierDismissible:!first,
  builder:(_)=>PopScope(canPop:!first, child:_MealChoice(prefs:prefs,first:first)));
class _MealChoice extends StatefulWidget {
  final SharedPreferences prefs;
  final bool first;
  const _MealChoice({required this.prefs,required this.first});
  @override State<_MealChoice> createState()=>_MealChoiceState();
}
class _MealChoiceState extends State<_MealChoice> {
  late String choice=readMealChoice(widget.prefs);
  late MealSchedule schedule=readMealSchedule(widget.prefs);
  bool saving=false;
  String? error;
  @override Widget build(BuildContext context)=>AlertDialog(
    title:LText(widget.first?'选择用餐时间':'用餐时间'),
    content:SizedBox(width:420,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const LText('按手机时间自动切换。'),
      const SizedBox(height:12),
      for(final item in {'auto':'跟随系统时间',...periodNames}.entries) ListTile(
        key:ValueKey('meal-choice-${item.key}'),title:LText(item.value),
        leading:Icon(choice==item.key?Icons.radio_button_checked:Icons.radio_button_unchecked),
        onTap:saving?null:()=>setState(()=>choice=item.key)),
      const LText('保存后可在设置中修改。'),
      const SizedBox(height:16),
      const LText('各餐开始时间'),
      for(var i=0;i<3;i++) ListTile(
        key:ValueKey('meal-time-$i'),title:LText('{meal}开始', params: {'meal': tr(context, periodNames.values.elementAt(i))}),
        trailing:Text(schedule.label(schedule.starts[i])),
        onTap:saving?null:() async {
          final selected=await showTimePicker(context:context,
            initialTime:TimeOfDay(hour:schedule.starts[i]~/60,minute:schedule.starts[i]%60),
            builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(alwaysUse24HourFormat:true),child:child!));
          if(selected!=null && mounted) setState(() {
            final values=schedule.starts; values[i]=selected.hour*60+selected.minute;
            schedule=MealSchedule(breakfast:values[0],lunch:values[1],dinner:values[2]);error=null;
          });
        }),
      LText('早餐 {breakfast}—{lunch}\n午餐 {lunch}—{dinner}\n晚餐 {dinner}—次日{breakfast}', params: {'breakfast': schedule.label(schedule.breakfast), 'lunch': schedule.label(schedule.lunch), 'dinner': schedule.label(schedule.dinner)}),
      if(!schedule.valid) const LText('请按早餐、午餐、晚餐的先后顺序设置，开始时间不能相同。',style:TextStyle(color:Colors.red)),
      TextButton(onPressed:saving?null:()=>setState(() {schedule=const MealSchedule();error=null;}),child:const LText('恢复默认时段')),

      if(error!=null) LText(error!,style:const TextStyle(color:Colors.red)),
    ]))),actions:[
      if(!widget.first) TextButton(onPressed:saving?null:()=>Navigator.pop(context),child:const LText('取消')),
      FilledButton(onPressed:saving || !schedule.valid?null:() async {
        setState(()=>saving=true);
        try {
          await saveMealConfig(widget.prefs,choice,schedule);
          if(context.mounted) Navigator.pop(context,choice);
        } catch(_) {if(mounted)setState(() {saving=false;error='保存失败，请重试';});}
      },child:LText(saving?'保存中…':'保存')),
    ]);
}
