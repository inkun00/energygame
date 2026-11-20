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

boardbytes=boardcount=board_dur=0
for f in Path('.godot/four-player-online').glob('*.log'):
    s=f.read_text()
    for m in re.finditer(r'\[BOARD_WINDOW\] begin (\d+) ([\d.]+)',s):
        end=re.search(r'\[BOARD_WINDOW\] end '+m[1]+r' ([\d.]+)',s[m.end():])
        if not end: continue
        a,b=float(m[2])+.5,float(end[1])-.5
        subset=[r for r in rows if a<=r[0]<b]
        n=sum(r[3] for r in subset)
        print('[BOARD_SEAT_WINDOW]',m[1],round(b-a,2),'seconds',n,'bytes',len(subset),'datagrams')
        boardbytes+=n
        boardcount+=len(subset)
        board_dur+=(b-a)
if board_dur < 40: raise SystemExit('Missing representative steady board windows on all four seats')
print('[BOARD_MEASURED]', boardbytes, 'payload bytes over', round(board_dur,3), 'seconds')
print('[BOARD_MODEL_20MIN] extra board time at measured quiet-board rate',round(tx + max(0,1200-elapsed)*boardbytes/board_dur), 'UDP payload bytes')
print('[BOARD_MODEL_20MIN] IPv4+UDP header-inclusive bytes',round(tx+28*len(rows)+max(0,1200-elapsed)*(boardbytes+28*boardcount)/board_dur))
