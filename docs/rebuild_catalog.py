"""Rebuild all unshipped menu additions, then apply meal periods."""
import runpy
from pathlib import Path
root=Path(__file__).resolve().parent
for script in ['import_wenying.py','import_baite.py','import_baite_chinese.py','import_fengwei.py','import_zhongxiaobei.py','classify_meal_periods.py']:
 runpy.run_path(str(root/script),run_name='__main__')
