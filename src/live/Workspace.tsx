import {createContext,useContext,useEffect,useState,type ReactNode} from 'react';
import {Navigate} from 'react-router-dom';
import {Brand,Copyright} from '../components/UI';
import {supabase} from '../lib/supabase';

type Workspace={profile:{id:string;first_name:string;last_name:string;email:string};organization:{id:string;name:string;contact_email:string|null;accent_color:string};role:string;reload:()=>Promise<void>};
const Context=createContext<Workspace|null>(null);
export const useWorkspace=()=>{const value=useContext(Context);if(!value)throw new Error('Workspace unavailable');return value};

export function WorkspaceGate({children}:{children:ReactNode}){
 const [loading,setLoading]=useState(true),[signedIn,setSignedIn]=useState(false),[profile,setProfile]=useState<any>(null),[membership,setMembership]=useState<any>(null),[error,setError]=useState('');
 const load=async()=>{if(!supabase){setError('Supabase is not configured.');setLoading(false);return}setLoading(true);setError('');const {data:{session}}=await supabase.auth.getSession();setSignedIn(!!session);if(!session){setProfile(null);setMembership(null);setLoading(false);return}const {data:m,error:me}=await supabase.from('organization_members').select('role,user_id,profiles!inner(id,first_name,last_name,email,auth_user_id),organizations(*)').eq('profiles.auth_user_id',session.user.id).eq('status','active').maybeSingle();if(me){setError(me.message);setLoading(false);return}if(m){const joined=Array.isArray(m.profiles)?m.profiles[0]:m.profiles;setProfile(joined);setMembership(m)}else{const {data:p,error:pe}=await supabase.from('profiles').select('id,first_name,last_name,email').eq('auth_user_id',session.user.id).maybeSingle();if(pe)setError(pe.message);setProfile(p);setMembership(null)}setLoading(false)};
 useEffect(()=>{let initialComplete=false;load().finally(()=>{initialComplete=true});const {data}=supabase!.auth.onAuthStateChange(event=>{if(event==='SIGNED_OUT'){setSignedIn(false);setProfile(null);setMembership(null);setLoading(false)}else if(event!=='INITIAL_SESSION'&&initialComplete)load()});return()=>data.subscription.unsubscribe()},[]);
 if(loading)return <div className="login"><main><div className="login-card"><Brand/><p>Opening your live workspace…</p></div></main></div>;
 if(!signedIn)return <Navigate to="/login" replace/>;
 if(error)return <div className="login"><main><div className="login-card"><Brand/><div className="error">{error}</div><button className="button" onClick={load}>Try again</button></div></main></div>;
 if(!membership)return <OrganizationSetup email={profile?.email||''} onDone={load}/>;
 const org=Array.isArray(membership.organizations)?membership.organizations[0]:membership.organizations;
 return <Context.Provider value={{profile,organization:org,role:membership.role,reload:load}}>{children}</Context.Provider>;
}

function OrganizationSetup({email,onDone}:{email:string;onDone:()=>Promise<void>}){const [busy,setBusy]=useState(false),[error,setError]=useState('');const submit=async(e:React.FormEvent<HTMLFormElement>)=>{e.preventDefault();setBusy(true);const fd=new FormData(e.currentTarget);const {error}=await supabase!.rpc('bootstrap_organization',{organization_name:String(fd.get('name')),contact_email:String(fd.get('email'))});setBusy(false);if(error)setError(error.message);else await onDone()};return <div className="login"><div className="login-art"><Brand/><div><span className="eyebrow">ONE QUICK STEP</span><h1>Create your volunteer workspace.</h1><p>This connects your opportunities and registrations to your live database.</p></div><Copyright/></div><main><div className="login-card"><Brand/><h1>Name your organization</h1><p>You can change these details later.</p>{error&&<div className="error">{error}</div>}<form onSubmit={submit}><label>Organization name<input name="name" required placeholder="e.g. DRS"/></label><label>Contact email<input name="email" type="email" required defaultValue={email}/></label><button disabled={busy} className="button primary submit">{busy?'Creating…':'Create workspace'}</button></form></div></main></div>}
