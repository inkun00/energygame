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

p=Path("scripts/tests/FourPlayerOnlineRulesTest.gd")
s=p.read_text()
needle='\tawait create_timer(0.15).timeout\n\tnm.request_roll_dice(idx)'
assert s.count(needle)==1
s=s.replace(needle,'\tprint("[BOARD_WINDOW] begin ", idx, " ", Time.get_unix_time_from_system())\n\tawait create_timer(12.15).timeout\n\tprint("[BOARD_WINDOW] end ", idx, " ", Time.get_unix_time_from_system())\n\tnm.request_roll_dice(idx)')
s=s.replace('"all seats answer a quiz", 45.0','"all seats answer a quiz", 115.0').replace('create_timer(230.0)','create_timer(315.0)')
p.write_text(s)
p=Path("scripts/tests/run_four_player_online_test.cjs")
s=p.read_text().replace('240_000', '320_000').replace('exceeded 240 seconds','exceeded 320 seconds')
p.write_text(s)
