import type {ReactNode} from 'react';
import {CheckCircle2,Clock3,AlertTriangle,XCircle} from 'lucide-react';
export function Brand({compact=false}:{compact?:boolean}){return <div className="brand"><span className="brand-mark">E</span>{!compact&&<span><b>VolunteerHQ</b><small>by Educational Apps Lab</small></span>}</div>}
export function Copyright({powered=false}:{powered?:boolean}){return <footer>{powered&&<span>Powered by Educational Apps Lab · </span>}© 2026 Educational Apps Lab. All rights reserved.</footer>}
export function Status({value}:{value:string}){const type=value.includes('attention')?'warn':value.includes('cancel')?'danger':value.includes('checked')||value.includes('published')||value.includes('final')?'success':'neutral';const Icon=type==='warn'?AlertTriangle:type==='danger'?XCircle:type==='success'?CheckCircle2:Clock3;return <span className={`status ${type}`}><Icon size={13}/>{value.replaceAll('-',' ')}</span>}
export function Metric({label,value,detail,icon}:{label:string;value:string|number;detail?:string;icon?:ReactNode}){return <div className="metric"><span className="metric-icon">{icon}</span><div><small>{label}</small><strong>{value}</strong>{detail&&<p>{detail}</p>}</div></div>}
export function Empty({title,body,action}:{title:string;body:string;action?:ReactNode}){return <div className="empty"><div className="empty-art">✦</div><h3>{title}</h3><p>{body}</p>{action}</div>}
export function Toast({message}:{message:string}){return <div className="toast" role="status"><CheckCircle2 size={18}/>{message}</div>}
