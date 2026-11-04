import {useEffect,useMemo,useRef,useState} from 'react';
import {Link,useParams} from 'react-router-dom';
import {ArrowLeft,CalendarDays,Check,Clock,Download,LogOut,ScanLine,Search,Usb,UserCheck,Users} from 'lucide-react';
import {Empty,Metric,Status} from '../components/UI';
import {supabase} from '../lib/supabase';
import {useWorkspace} from './Workspace';

type Volunteer={id:string;first_name:string;last_name:string;email:string;phone:string|null;school_organization:string|null;created_at:string;registrations:{count:number}[]};
type ReportEvent={id:string;name:string;date:string;registrations:{count:number}[];attendance_sessions:{count:number}[];service_awards:{awarded_minutes:number}[]};
type Member={id:string;role:string;status:string;profiles:{first_name:string;last_name:string;email:string}|{first_name:string;last_name:string;email:string}[]};

export function LiveVolunteerDirectory(){const {organization}=useWorkspace();const [rows,setRows]=useState<Volunteer[]>([]),[loading,setLoading]=useState(true),[q,setQ]=useState('');useEffect(()=>{supabase!.from('volunteers').select('id,first_name,last_name,email,phone,school_organization,created_at,registrations(count)').eq('organization_id',organization.id).order('last_name').then(({data})=>{setRows((data||[]) as Volunteer[]);setLoading(false)})},[organization.id]);const shown=useMemo(()=>rows.filter(v=>`${v.first_name} ${v.last_name} ${v.email} ${v.school_organization||''}`.toLowerCase().includes(q.toLowerCase())),[q,rows]);return <><div className="page-head"><div><span className="eyebrow">PEOPLE</span><h1>Volunteers</h1><p>Live organization-wide volunteer records and registrations.</p></div></div><div className="toolbar"><label className="search"><Search/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search volunteers…"/></label></div>{loading?<section className="panel">Loading volunteers…</section>:shown.length===0?<section className="panel"><Empty title="No volunteers yet" body="Volunteer profiles appear here after the first registration."/></section>:<section className="panel table-panel"><table><thead><tr><th>Volunteer</th><th>Organization</th><th>Phone</th><th>Registrations</th><th>Added</th></tr></thead><tbody>{shown.map(v=><tr key={v.id}><td><b>{v.first_name} {v.last_name}</b><small>{v.email}</small></td><td>{v.school_organization||'—'}</td><td>{v.phone||'—'}</td><td><b>{v.registrations?.[0]?.count||0}</b></td><td>{new Date(v.created_at).toLocaleDateString()}</td></tr>)}</tbody></table></section>}</>}

export function LiveReports(){const {organization}=useWorkspace();const [rows,setRows]=useState<ReportEvent[]>([]),[loading,setLoading]=useState(true);useEffect(()=>{supabase!.from('events').select('id,name,date,registrations(count),attendance_sessions(count),service_awards(awarded_minutes)').eq('organization_id',organization.id).order('date',{ascending:false}).then(({data})=>{setRows((data||[]) as ReportEvent[]);setLoading(false)})},[organization.id]);const totals=rows.reduce((a,e)=>({registrations:a.registrations+(e.registrations?.[0]?.count||0),attendance:a.attendance+(e.attendance_sessions?.[0]?.count||0),minutes:a.minutes+(e.service_awards||[]).reduce((n,x)=>n+x.awarded_minutes,0)}),{registrations:0,attendance:0,minutes:0});const exportCsv=()=>{const lines=[['Event','Date','Registrations','Attendance sessions','Awarded hours'],...rows.map(e=>[e.name,e.date,String(e.registrations?.[0]?.count||0),String(e.attendance_sessions?.[0]?.count||0),((e.service_awards||[]).reduce((n,x)=>n+x.awarded_minutes,0)/60).toFixed(2)])];const blob=new Blob([lines.map(line=>line.map(value=>`"${value.replaceAll('"','""')}"`).join(',')).join('\n')],{type:'text/csv'});const link=document.createElement('a');link.href=URL.createObjectURL(blob);link.download='volunteer-report.csv';link.click();URL.revokeObjectURL(link.href)};return <><div className="page-head"><div><span className="eyebrow">INSIGHTS</span><h1>Reports</h1><p>Live participation and awarded service across your opportunities.</p></div><button className="button" onClick={exportCsv} disabled={!rows.length}><Download/>Export CSV</button></div><div className="metrics"><Metric label="Opportunities" value={rows.length} detail="All database records" icon={<CalendarDays/>}/><Metric label="Registrations" value={totals.registrations} detail="Across all opportunities" icon={<Users/>}/><Metric label="Attendance sessions" value={totals.attendance} detail="Recorded check-ins" icon={<UserCheck/>}/><Metric label="Awarded service" value={`${(totals.minutes/60).toFixed(1)}h`} detail="Finalized and draft awards" icon={<Clock/>}/></div>{loading?<section className="panel">Loading reports…</section>:<section className="panel table-panel"><table><thead><tr><th>Opportunity</th><th>Date</th><th>Registrations</th><th>Attendance</th><th>Awarded hours</th></tr></thead><tbody>{rows.map(e=><tr key={e.id}><td><Link to={`/app/events/${e.id}`}><b>{e.name}</b></Link></td><td>{new Date(`${e.date}T12:00:00`).toLocaleDateString()}</td><td>{e.registrations?.[0]?.count||0}</td><td>{e.attendance_sessions?.[0]?.count||0}</td><td>{((e.service_awards||[]).reduce((n,x)=>n+x.awarded_minutes,0)/60).toFixed(1)}</td></tr>)}</tbody></table>{!rows.length&&<Empty title="No report data yet" body="Create an opportunity and accept registrations to begin reporting."/>}</section>}</>}

export function LiveUsers(){const {organization}=useWorkspace();const [rows,setRows]=useState<Member[]>([]),[loading,setLoading]=useState(true);useEffect(()=>{supabase!.from('organization_members').select('id,role,status,profiles!inner(first_name,last_name,email)').eq('organization_id',organization.id).order('created_at').then(({data})=>{setRows((data||[]) as Member[]);setLoading(false)})},[organization.id]);return <><div className="page-head"><div><span className="eyebrow">ACCESS CONTROL</span><h1>Users & permissions</h1><p>People who currently have access to this workspace.</p></div></div>{loading?<section className="panel">Loading users…</section>:<section className="panel table-panel"><table><thead><tr><th>User</th><th>Role</th><th>Access</th><th>Status</th></tr></thead><tbody>{rows.map(member=>{const p=Array.isArray(member.profiles)?member.profiles[0]:member.profiles;return <tr key={member.id}><td><b>{p.first_name} {p.last_name}</b><small>{p.email}</small></td><td>{member.role.replaceAll('_',' ')}</td><td>Organization workspace</td><td><Status value={member.status}/></td></tr>})}</tbody></table></section>}<p className="quiet-note">Invitations are not enabled yet. Existing owners and staff are shown from the live database.</p></>}

type RosterRow={id:string;status:string;volunteers:{first_name:string;last_name:string;email:string}|{first_name:string;last_name:string;email:string}[];attendance_sessions:{id:string;checked_in_at:string;checked_out_at:string|null;status:string}[]};
type ScanMode='checkin'|'checkout';
type ScanFeedback={action:string;volunteer_first_name:string|null;volunteer_last_name:string|null;occurred_at:string;message:string};

function scannerToken(value:string){
 const raw=value.trim();
 if(!raw)return '';
 try{
  const url=new URL(raw);
  const marker='/registration/';
  const markerIndex=url.pathname.toLowerCase().indexOf(marker);
  if(markerIndex>=0)return decodeURIComponent(url.pathname.slice(markerIndex+marker.length));
 }catch{/* A plain secure token is the normal scanner value. */}
 return raw;
}

function scannerTone(success:boolean){
 try{
  const AudioContextClass=window.AudioContext||(window as typeof window&{webkitAudioContext?:typeof AudioContext}).webkitAudioContext;
  if(!AudioContextClass)return;
  const audio=new AudioContextClass();
  const oscillator=audio.createOscillator();
  const gain=audio.createGain();
  oscillator.connect(gain);gain.connect(audio.destination);
  oscillator.frequency.value=success?880:220;
  gain.gain.setValueAtTime(.12,audio.currentTime);
  gain.gain.exponentialRampToValueAtTime(.001,audio.currentTime+.18);
  oscillator.start();oscillator.stop(audio.currentTime+.18);
  oscillator.addEventListener('ended',()=>audio.close());
 }catch{/* Audio confirmation is helpful but not required for scanning. */}
}

export function LiveEventMode(){
 const {eventId}=useParams();
 const {organization,profile}=useWorkspace();
 const [event,setEvent]=useState<{name:string}|null>(null),[rows,setRows]=useState<RosterRow[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState('');
 const [scannerActive,setScannerActive]=useState(false),[scanMode,setScanMode]=useState<ScanMode>('checkin'),[scanValue,setScanValue]=useState(''),[scanBusy,setScanBusy]=useState(false),[feedback,setFeedback]=useState<ScanFeedback|null>(null);
 const [deviceSession]=useState(()=>crypto.randomUUID());
 const scannerInput=useRef<HTMLInputElement>(null);

 const load=async(silent=false)=>{
  if(!silent)setLoading(true);
  const [eventResult,rosterResult]=await Promise.all([
   supabase!.from('events').select('name').eq('id',eventId!).eq('organization_id',organization.id).single(),
   supabase!.from('registrations').select('id,status,volunteers!inner(first_name,last_name,email),attendance_sessions(id,checked_in_at,checked_out_at,status)').eq('event_id',eventId!).order('created_at')
  ]);
  if(eventResult.error||rosterResult.error)setError(eventResult.error?.message||rosterResult.error?.message||'Unable to load event day.');
  else{setEvent(eventResult.data);setRows((rosterResult.data||[]) as RosterRow[])}
  if(!silent)setLoading(false);
 };

 useEffect(()=>{load()},[eventId,organization.id]);
 useEffect(()=>{if(scannerActive)setTimeout(()=>scannerInput.current?.focus(),0)},[scannerActive,scanMode]);

 const toggle=async(row:RosterRow)=>{
  setError('');
  const open=row.attendance_sessions.find(x=>!x.checked_out_at&&x.status==='open');
  const result=open
   ?await supabase!.from('attendance_sessions').update({checked_out_at:new Date().toISOString(),check_out_method:'manual',checked_out_by:profile.id,status:'closed'}).eq('id',open.id)
   :await supabase!.from('attendance_sessions').insert({organization_id:organization.id,event_id:eventId!,registration_id:row.id,checked_in_at:new Date().toISOString(),check_in_method:'manual',checked_in_by:profile.id,status:'open'});
  if(result.error)setError(result.error.message);else await load(true);
 };

 const scan=async()=>{
  const token=scannerToken(scanValue);
  if(!token||scanBusy)return;
  setScanBusy(true);setError('');setFeedback(null);setScanValue('');
  const {data,error:scanError}=await supabase!.rpc('scan_event_credential',{event_id:eventId!,secure_token:token,scan_mode:scanMode,device_session:deviceSession});
  if(scanError){
   setError(scanError.message);scannerTone(false);
  }else{
   const result=(Array.isArray(data)?data[0]:data) as ScanFeedback|undefined;
   if(result){
    setFeedback(result);
    const success=result.action==='checked_in'||result.action==='checked_out';
    scannerTone(success);
    if(success)await load(true);
   }
  }
  setScanBusy(false);
  setTimeout(()=>scannerInput.current?.focus(),0);
 };

 const checkedIn=rows.filter(r=>r.attendance_sessions.some(x=>!x.checked_out_at&&x.status==='open')).length;
 const feedbackSuccess=feedback?.action==='checked_in'||feedback?.action==='checked_out';
 if(loading)return <section className="panel">Opening event day…</section>;
 return <>
  <Link className="back dashboard-return" to={`/app/events/${eventId}`}><ArrowLeft/>Back to opportunity</Link>
  <div className="page-head"><div><span className="eyebrow">EVENT DAY</span><h1>{event?.name||'Opportunity'}</h1><p>Scan volunteer credentials or use the live roster for manual attendance.</p></div></div>
  {error&&<div className="error">{error}</div>}
  <section className={`panel scanner-station ${scannerActive?'active':''}`}>
   <div className="scanner-heading"><div className="scanner-icon"><Usb/></div><div><span className="eyebrow">WIRED USB QR SCANNER</span><h2>{scannerActive?'Scanner station ready':'Connect your scanner'}</h2><p>{scannerActive?'Keep this page open. Scan each volunteer’s QR code from their phone.':'Plug in the scanner, then start the station. No driver or pairing is required.'}</p></div><button type="button" className={scannerActive?'button':'button primary'} onClick={()=>{setScannerActive(value=>!value);setFeedback(null)}}>{scannerActive?'Stop scanner':'Start USB scanner'}</button></div>
   {scannerActive&&<div className="scanner-console">
    <div className="scan-mode" role="group" aria-label="Scanner action"><button type="button" className={scanMode==='checkin'?'active':''} onClick={()=>setScanMode('checkin')}><Check/>Check in</button><button type="button" className={scanMode==='checkout'?'active':''} onClick={()=>setScanMode('checkout')}><LogOut/>Check out</button></div>
    <label className="scanner-input"><ScanLine/><span><b>{scanBusy?'Processing scan…':'Scanner input ready'}</b><small>The scanner should type the code and press Enter automatically.</small></span><input ref={scannerInput} value={scanValue} onChange={e=>setScanValue(e.target.value)} onKeyDown={e=>{if(e.key==='Enter'){e.preventDefault();scan()}}} onBlur={()=>setTimeout(()=>scannerInput.current?.focus(),80)} disabled={scanBusy} autoComplete="off" aria-label="USB scanner input"/></label>
    {feedback&&<div className={`scan-feedback ${feedbackSuccess?'success':'warning'}`} role="status"><span>{feedbackSuccess?<Check/>:<ScanLine/>}</span><div><b>{feedback.message}</b><small>{new Date(feedback.occurred_at).toLocaleTimeString([],{hour:'numeric',minute:'2-digit',second:'2-digit'})} · {feedbackSuccess?(feedback.action==='checked_in'?'Attendance check-in recorded':'Attendance checkout recorded'):'No attendance change was made'}</small></div></div>}
   </div>}
  </section>
  <div className="metrics"><Metric label="Registered" value={rows.length} icon={<Users/>}/><Metric label="Currently checked in" value={checkedIn} icon={<UserCheck/>}/><Metric label="Not checked in" value={rows.length-checkedIn} icon={<Clock/>}/></div>
  <section className="panel table-panel"><div className="section-head"><div><h2>Live attendance roster</h2><p>Manual controls remain available if a QR code cannot be scanned.</p></div></div><table><thead><tr><th>Volunteer</th><th>Registration</th><th>Attendance</th><th></th></tr></thead><tbody>{rows.map(row=>{const v=Array.isArray(row.volunteers)?row.volunteers[0]:row.volunteers;const open=row.attendance_sessions.find(x=>!x.checked_out_at&&x.status==='open');return <tr key={row.id}><td><b>{v.first_name} {v.last_name}</b><small>{v.email}</small></td><td><Status value={row.status}/></td><td>{open?<>Checked in<small>{new Date(open.checked_in_at).toLocaleTimeString([],{hour:'numeric',minute:'2-digit'})}</small></>:'Not currently checked in'}</td><td><button className={open?'button':'button primary'} onClick={()=>toggle(row)}>{open?<><LogOut/>Check out</>:<><Check/>Check in</>}</button></td></tr>})}</tbody></table>{!rows.length&&<Empty title="No registered volunteers" body="Registrations will appear here automatically."/>}</section>
 </>
}
