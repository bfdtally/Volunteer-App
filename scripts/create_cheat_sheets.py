from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output'/'pdf'; OUT.mkdir(parents=True,exist_ok=True)
NAVY=colors.HexColor('#163a5f'); ORANGE=colors.HexColor('#ef7b45'); LIGHT=colors.HexColor('#f1f5f7'); MUTED=colors.HexColor('#5f7180'); GREEN=colors.HexColor('#247a57')
styles=getSampleStyleSheet()
styles.add(ParagraphStyle(name='TitleEAL',parent=styles['Title'],fontName='Helvetica-Bold',fontSize=22,leading=25,textColor=NAVY,spaceAfter=5))
styles.add(ParagraphStyle(name='Sub',parent=styles['Normal'],fontSize=9,leading=11,textColor=MUTED,spaceAfter=8))
styles.add(ParagraphStyle(name='H2EAL',parent=styles['Heading2'],fontName='Helvetica-Bold',fontSize=12.5,leading=14,textColor=NAVY,spaceBefore=7,spaceAfter=4))
styles.add(ParagraphStyle(name='Step',parent=styles['Normal'],fontSize=9.2,leading=12,textColor=colors.HexColor('#17324b')))
styles.add(ParagraphStyle(name='Callout',parent=styles['Normal'],fontSize=8.6,leading=11,textColor=NAVY))
styles.add(ParagraphStyle(name='FooterEAL',parent=styles['Normal'],fontSize=7.5,leading=9,textColor=MUTED,alignment=TA_CENTER))

def footer(canvas,doc):
    canvas.saveState(); canvas.setStrokeColor(colors.HexColor('#d9e2e8')); canvas.line(.65*inch,.52*inch,7.85*inch,.52*inch)
    canvas.setFont('Helvetica',7.5); canvas.setFillColor(MUTED); canvas.drawString(.65*inch,.34*inch,'Educational Apps Lab - VolunteerHQ')
    canvas.drawRightString(7.85*inch,.34*inch,f'Page {doc.page}  |  Updated November 6, 2026'); canvas.restoreState()

def header(story,title,audience):
    story.extend([Paragraph('EDUCATIONAL APPS LAB',ParagraphStyle('brand',fontName='Helvetica-Bold',fontSize=9,textColor=ORANGE,leading=11,spaceAfter=6)),Paragraph(title,styles['TitleEAL']),Paragraph(audience,styles['Sub'])])

def h(story,text): story.append(Paragraph(text,styles['H2EAL']))
def bullets(story,items):
    data=[]
    for i,item in enumerate(items,1): data.append([Paragraph(str(i),ParagraphStyle(f'n{i}',fontName='Helvetica-Bold',fontSize=9,textColor=colors.white,alignment=TA_CENTER)),Paragraph(item,styles['Step'])])
    table=Table(data,colWidths=[.28*inch,6.7*inch],hAlign='LEFT')
    table.setStyle(TableStyle([('VALIGN',(0,0),(-1,-1),'TOP'),('BACKGROUND',(0,0),(0,-1),NAVY),('BOX',(0,0),(0,-1),0,NAVY),('LEFTPADDING',(0,0),(0,-1),5),('RIGHTPADDING',(0,0),(0,-1),5),('TOPPADDING',(0,0),(-1,-1),3),('BOTTOMPADDING',(0,0),(-1,-1),3),('ROWBACKGROUNDS',(1,0),(1,-1),[colors.white,LIGHT])]))
    story.append(table)
def callout(story,title,text,color=ORANGE):
    t=Table([[Paragraph(f'<b>{title}</b><br/>{text}',styles['Callout'])]],colWidths=[7*inch]);t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,-1),colors.HexColor('#fff5ef')),('BOX',(0,0),(-1,-1),1,color),('LEFTPADDING',(0,0),(-1,-1),10),('RIGHTPADDING',(0,0),(-1,-1),10),('TOPPADDING',(0,0),(-1,-1),6),('BOTTOMPADDING',(0,0),(-1,-1),6)]));story.extend([Spacer(1,5),t])
def make(filename,title,audience,sections,notes=[]):
    path=OUT/filename;doc=SimpleDocTemplate(str(path),pagesize=letter,rightMargin=.7*inch,leftMargin=.7*inch,topMargin=.5*inch,bottomMargin=.65*inch,title=title,author='Educational Apps Lab')
    story=[];header(story,title,audience)
    for heading,items in sections:
        h(story,heading);bullets(story,items)
    for title_,text_ in notes:callout(story,title_,text_)
    story.extend([Spacer(1,8),Paragraph('© 2026 Educational Apps Lab. All rights reserved.',styles['FooterEAL'])]);doc.build(story,onFirstPage=footer,onLaterPages=footer);return path

files=[]
files.append(make('VolunteerHQ_Volunteer_Cheat_Sheet.pdf','Volunteer Quick Guide','For registered volunteers using the currently live VolunteerHQ workflow.',[
 ('Before the event',['Open the event registration link provided by the organizer.','Choose the event day or days you can attend when the event has multiple dates.','Enter your name, email, phone, and school/organization as requested, agree to the guidelines, and select <b>Complete registration</b>.','Save the QR credential shown after registration. Keep it available on your phone for event day.']),
 ('At check-in',['Open your saved QR credential and increase phone brightness if needed.','Present the full QR code to the check-in staff. Hold the phone still until staff confirms the scan.','Listen for the staff confirmation. Do not walk away until your name shows as checked in.','If the scanner cannot read the code, give staff your name or email for manual lookup.']),
 ('At checkout',['Return to the check-in station before leaving when checkout is required.','Present the same QR credential. Staff switches the station to <b>Check out</b> before scanning.','Confirm that staff sees the checkout message before leaving.'])
],[('Important','A volunteer QR works only in Volunteer Event Mode. It will not check in an event participant.')]))
files.append(make('VolunteerHQ_Participant_Family_Group_Cheat_Sheet.pdf','Participant Registration Quick Guide','For parents, guardians, participants, school coordinators, and group leaders using currently live features.',[
 ('Choose the correct registration',['Open the public event page.','Select <b>Attend the event</b> for participants. Do not use <b>Help with the event</b> unless registering as a volunteer.','Choose <b>Individual or family</b> or <b>School or organized group</b>, depending on the options enabled by the organizer.']),
 ('Individual or family',['Enter the parent/guardian information once.','Enter each child separately. Use <b>Add another participant</b> for siblings or multiple children.','Review school and grade information, then complete registration.','Save every child\'s individual QR credential. Each child has a separate attendance record.']),
 ('School or group',['Enter the school/group and coordinator information.','Add roster members one at a time.','Complete registration and save the group QR plus each participant QR shown on the confirmation page.','At event arrival, present the group QR to staff. Staff must confirm individual attendance on the roster.']),
 ('Event day',['Bring the saved credential on a phone or printed page. Children do not need accounts or phones.','If a person arrives separately from a group, staff can use that participant\'s individual credential or manual roster control.'])
],[('Currently live','Manual family and school/group registration, individual participant credentials, group credentials, participant scanning, and manual individual attendance are live.'),('Not yet available','CSV roster upload, confirmation email delivery, and full family/group batch controls are still being completed. Enter group rosters manually for now.')]))
files.append(make('VolunteerHQ_Check_In_Staff_Cheat_Sheet.pdf','Check-In Staff Quick Guide','For staff operating the currently live Volunteer and Participant scanning stations.',[
 ('Open the right station',['Sign in to VolunteerHQ and open <b>Opportunities</b>.','Open the event record.','Use <b>Event Day Scanning Station</b> for volunteers.','Use <b>Participant Scanning Station</b> for participants and groups when participant registration is enabled. Never mix the two stations.']),
 ('Scan with the USB scanner',['Connect the wired scanner. It behaves like a keyboard.','Keep the correct station open and click the scanner input if needed.','Choose <b>Check in</b> or <b>Check out</b> before scanning.','Scan the credential from the attendee\'s phone. Wait for the on-screen result before scanning the next person.']),
 ('Manual attendance',['Use the live roster when a credential is unavailable or difficult to scan.','Match the person carefully using name, school, grade, or email as shown.','Select <b>Check in</b> or <b>Check out</b> on that person\'s row.','For a group QR, the currently live station identifies the group; confirm individual participants in the roster rather than recording one shared attendance entry.']),
 ('If something goes wrong',['Wrong QR type: move to the correct Volunteer or Participant station.','Already checked in / not checked in: verify the station mode and person before changing anything.','Scanner trouble: use manual roster controls. Do not repeatedly scan the same code.','Internet trouble: do not promise that attendance saved unless the station shows confirmation.'])
],[('Privacy','Show only the information needed to identify and check in the attendee. Never read guardian or emergency contact information aloud.'),('Currently being improved','Duplicate-scan protection, group batch actions, participant search, and walk-in tools are under active development and should not be treated as deployed until the organizer confirms an update.')]))
files.append(make('VolunteerHQ_Organizer_Cheat_Sheet.pdf','Organizer Quick Guide','For event owners, administrators, and coordinators using the currently live VolunteerHQ organizer workspace.',[
 ('Create or configure an event',['Sign in and select <b>Create opportunity</b>, or open an existing opportunity and choose <b>Edit opportunity</b>.','Complete event details, dates, times, locations, volunteer setup, and branding.','On the Registration step, turn on <b>Accept event participants</b> when needed.','Enable <b>Individual / family</b>, <b>School / group</b>, or both. Set participant capacity and required school, grade, guardian, emergency, checkout, walk-in, and credential options.','Publish or save the opportunity.']),
 ('Share the public page',['Open the opportunity and select <b>Public page</b>.','Participants use <b>Attend the event</b>; volunteers use <b>Help with the event</b>.','Test both enabled registration paths before distributing the link.']),
 ('Prepare for event day',['Open the event record and verify volunteer and participant counts separately.','Use the Volunteer Event Day station for volunteer QR credentials.','Use the Participant Scanning Station for participant/group credentials.','Keep manual roster controls available at every station and confirm each device is signed in before doors open.']),
 ('Monitor records',['Use <b>Volunteers</b> for volunteer records and <b>Participants</b> for participant records.','Do not use participant attendance for volunteer service credit, letters, or certificates.','If a registration or scan needs correction, document the reason and restrict changes to authorized staff.'])
],[('Currently live','Event participant settings, family/group public registration, separate participant records, credentials, participant scanning, and individual attendance are deployed.'),('Still under development','CSV roster import, advanced participant reports, confirmation email delivery, granular event staff assignments, walk-in tools, and full family/group batch attendance. Do not promise these until the deployment is confirmed.')]))
print('\n'.join(str(p) for p in files))
