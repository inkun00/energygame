from pathlib import Path
p=Path("scripts/tests/FourPlayerOnlineRulesTest.gd")
s=p.read_text()
needle='\t\tawait create_timer(0.35).timeout'
assert s.count(needle)==1
s=s.replace(needle,'\t\tprint("[WINDOW] begin ", game_id, " ", Time.get_unix_time_from_system())\n'+needle)
needle='\t\t_check_same_reports("result_%d" % round_id)'
assert s.count(needle)==1
s=s.replace(needle,'\t\tprint("[WINDOW] end ", game_id, " ", Time.get_unix_time_from_system())\n'+needle)
p.write_text(s)
