from pathlib import Path
import re,json,collections
rows=[]
for line in Path('/tmp/game-packets.log').read_text().splitlines():
    m=re.search(r'^([\d.]+) IP6? .*?\.(\d+) > .*?\.(\d+): UDP, length (\d+)',line)
    if m: rows.append((float(m[1]),int(m[2]),int(m[3]),int(m[4])))
if not rows: raise SystemExit('No filtered gameplay datagrams observed')
tx=sum(p[3] for p in rows)
elapsed=rows[-1][0]-rows[0][0]
def info(rs):
    return {"packets":len(rs),"udp_payload_bytes":sum(p[3] for p in rs),"with_ipv4_udp_headers_bytes":sum(p[3]+28 for p in rs)}
print('[MATCH_BANDWIDTH] total',json.dumps(info(rows)),'elapsed',round(elapsed,3))
print('[MATCH_BANDWIDTH] host_sent',json.dumps(info([p for p in rows if p[1]==18921])))
print('[MATCH_BANDWIDTH] guests_sent',json.dumps(info([p for p in rows if p[2]==18921])))
byflow=collections.defaultdict(list)
for p in rows: byflow[p[2] if p[1]==18921 else p[1]].append(p)
for i,(port,rs) in enumerate(byflow.items()):
    print('[FLOW]',i+1,'host_to_seat',info([p for p in rs if p[1]==18921]),'seat_to_host',info([p for p in rs if p[2]==18921]))
roles=[]
for f in Path('.godot/four-player-online').glob('*.log'):
    s=f.read_text()
    for line in s.splitlines():
        if '[GAME_ARGUMENT_BYTES]' in line or '[UDP_IO]' in line or '[PASS] Four-player online rules' in line: print(line)
    role=re.search(r'\[UDP_IO\] role=(\w+) tx=(\d+) rx=(\d+) packets_tx=(\d+) packets_rx=(\d+)',s)
    if role: roles.append(int(role[2]))
if all(roles) and len(roles)==4:
    print('[CROSSCHECK] summed sender UDP payload by process',sum(roles),'passive capture',tx)
    if abs(sum(roles)-tx)>0.001*tx: raise SystemExit('Independent UDP measures disagree')
s=Path('.godot/four-player-online/host.log').read_text()
for game in ['solar_align','eco_commute']:
    begin=re.search(r'\[WINDOW\] begin '+game+r' ([\d.]+)',s)
    end=re.search(r'\[WINDOW\] end '+game+r' ([\d.]+)',s)
    if begin and end:
        a,b=float(begin[1])+1,float(end[1])-1
        subset=[p for p in rows if a<=p[0]<b]
        if b>a:
            print('[STEADY_MINIGAME]',game,'seconds',round(b-a,3),'UDP',json.dumps(info(subset)),'extra_20min_projection',round(tx+max(0,1200-elapsed)*sum(p[3] for p in subset)/(b-a)))
print('[MODEL] 20min repeating this QA action mix, UDP payload bytes',round(tx*1200/elapsed))
