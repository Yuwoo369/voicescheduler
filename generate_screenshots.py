#!/usr/bin/env python3
"""App Store Screenshots - 1284x2778 (iPhone 6.5")"""
from PIL import Image, ImageDraw, ImageFont
import math, os

W, H = 1284, 2778
BG_TOP = (15, 20, 40)
BG_BOT = (25, 35, 65)
GOLD = (218, 175, 75)
GOLD_L = (240, 210, 120)
WHITE = (255, 255, 255)
CARD = (35, 45, 80)
GREEN = (80, 200, 120)
RED = (230, 80, 80)
ORANGE = (240, 160, 50)

def font(size):
    try: return ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", size)
    except: return ImageFont.load_default()

def bg(draw):
    for y in range(H):
        r = y / H
        draw.line([(0,y),(W,y)], fill=tuple(int(BG_TOP[i]+(BG_BOT[i]-BG_TOP[i])*r) for i in range(3)))

def ctxt(draw, y, text, sz, color):
    f = font(sz)
    bb = draw.textbbox((0,0), text, font=f)
    draw.text(((W-(bb[2]-bb[0]))//2, y), text, fill=color, font=f)

def ltxt(draw, x, y, text, sz, color):
    draw.text((x, y), text, fill=color, font=font(sz))

def mic(draw, cx, cy, r, color):
    mw, mh = int(r*0.4), int(r*0.6)
    draw.rounded_rectangle([cx-mw,cy-mh,cx+mw,cy+int(mh*0.2)], radius=mw, fill=color)
    draw.arc([cx-int(mw*1.5),cy-int(mh*0.2),cx+int(mw*1.5),cy+int(mh*0.8)], 0, 180, fill=color, width=max(3,int(r*0.06)))
    sw = max(2, int(r*0.04))
    st = cy+int(mh*0.8); sb = st+int(r*0.25)
    draw.rectangle([cx-sw,st,cx+sw,sb], fill=color)
    draw.line([(cx-int(mw*0.8),sb),(cx+int(mw*0.8),sb)], fill=color, width=sw)

def ss1():
    img = Image.new('RGB',(W,H),BG_TOP); draw = ImageDraw.Draw(img); bg(draw)
    ctxt(draw,180,"Speak Your Schedule",72,WHITE)
    ctxt(draw,280,"AI Does the Rest",72,GOLD)
    cx,cy = W//2,750; r=200
    for i in range(3):
        ri=r+40+i*35
        draw.ellipse([cx-ri,cy-ri,cx+ri,cy+ri], outline=(*GOLD,60-i*20), width=3)
    draw.ellipse([cx-r,cy-r,cx+r,cy+r], fill=GOLD)
    mic(draw,cx,cy-20,r,WHITE)
    draw.rounded_rectangle([100,1050,W-100,1210], radius=20, fill=CARD)
    ctxt(draw,1080,'"Team meeting tomorrow at 2pm"',44,WHITE)
    ctxt(draw,1145,"Recognized",32,GOLD_L)
    ctxt(draw,1350,"Extracted Tasks",48,WHITE)
    ty=1430
    for title,time,pri,c in [("Team Meeting","Tomorrow 2:00 PM","High",RED),("Submit Report","Friday 5:00 PM","Medium",ORANGE),("Gym","Every Monday 7 PM","Low",GREEN)]:
        draw.rounded_rectangle([100,ty,W-100,ty+140], radius=16, fill=CARD)
        draw.ellipse([140,ty+50,170,ty+80], fill=c)
        ltxt(draw,200,ty+30,title,40,WHITE); ltxt(draw,200,ty+85,time,30,GOLD_L)
        draw.rounded_rectangle([W-300,ty+45,W-140,ty+90], radius=12, fill=c)
        ltxt(draw,W-280,ty+50,pri,28,WHITE)
        ty+=170
    draw.rounded_rectangle([200,2400,W-200,2490], radius=30, fill=GOLD)
    ctxt(draw,2420,"Register to Calendar",42,BG_TOP)
    ctxt(draw,2580,"Voice Scheduler",38,WHITE); ctxt(draw,2640,"AI-Powered Schedule Management",30,GOLD_L)
    return img

def ss2():
    img = Image.new('RGB',(W,H),BG_TOP); draw = ImageDraw.Draw(img); bg(draw)
    ctxt(draw,180,"AI Analyzes",72,WHITE); ctxt(draw,280,"Your Priorities",72,GOLD)
    cx,cy=W//2,620
    for a in range(0,360,45):
        rad=math.radians(a)
        draw.line([(cx+int(60*math.cos(rad)),cy+int(60*math.sin(rad))),(cx+int(120*math.cos(rad)),cy+int(120*math.sin(rad)))], fill=GOLD_L, width=4)
    draw.ellipse([cx-50,cy-50,cx+50,cy+50], fill=GOLD)
    ctxt(draw,cy-22,"AI",44,BG_TOP)
    ty=850
    for pl,title,time,reason,c in [("High Priority","Team Meeting","Tomorrow 2:00 PM","Peak focus time recommended",RED),("Medium Priority","Submit Report","Friday 5:00 PM","Deadline-based scheduling",ORANGE),("Low Priority","Gym","Monday 7:00 PM","Routine pattern detected",GREEN)]:
        draw.rounded_rectangle([80,ty,W-80,ty+280], radius=20, fill=CARD)
        draw.rounded_rectangle([80,ty,96,ty+280], radius=5, fill=c)
        draw.rounded_rectangle([130,ty+20,130+len(pl)*22,ty+65], radius=10, fill=(*c,80))
        ltxt(draw,145,ty+25,pl,30,c)
        ltxt(draw,130,ty+85,title,46,WHITE); ltxt(draw,130,ty+150,time,34,GOLD_L)
        ltxt(draw,130,ty+210,f"* {reason}",28,WHITE)
        ty+=320
    ctxt(draw,2580,"Voice Scheduler",38,WHITE); ctxt(draw,2640,"Smart Priority Detection",30,GOLD_L)
    return img

def ss3():
    img = Image.new('RGB',(W,H),BG_TOP); draw = ImageDraw.Draw(img); bg(draw)
    ctxt(draw,180,"Auto-Sync to",72,WHITE); ctxt(draw,280,"Google Calendar",72,GOLD)
    cx,cy=100,480; cw,ch=W-200,1600
    draw.rounded_rectangle([cx,cy,cx+cw,cy+ch], radius=24, fill=CARD)
    draw.rounded_rectangle([cx,cy,cx+cw,cy+100], radius=24, fill=GOLD)
    draw.rectangle([cx,cy+70,cx+cw,cy+100], fill=GOLD)
    ctxt(draw,cy+25,"February 2026",44,BG_TOP)
    days=["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
    dw=cw//7
    for i,d in enumerate(days):
        ltxt(draw,cx+i*dw+dw//2-20,cy+120,d,28,WHITE)
    for day in range(1,29):
        col=(day-1)%7; row=(day-1)//7
        dx=cx+col*dw+15; dy=cy+180+row*200
        ltxt(draw,dx,dy,str(day),30,WHITE if day!=15 else GOLD)
        if day==16:
            draw.rounded_rectangle([dx-5,dy+40,dx+dw-25,dy+72], radius=6, fill=RED)
            ltxt(draw,dx+5,dy+44,"Meeting",22,WHITE)
        elif day==20:
            draw.rounded_rectangle([dx-5,dy+40,dx+dw-25,dy+72], radius=6, fill=ORANGE)
            ltxt(draw,dx+5,dy+44,"Report",22,WHITE)
        if day in [9,16,23]:
            draw.rounded_rectangle([dx-5,dy+80,dx+dw-25,dy+112], radius=6, fill=GREEN)
            ltxt(draw,dx+5,dy+84,"Gym",22,WHITE)
    draw.rounded_rectangle([150,2200,W-150,2320], radius=20, fill=(30,80,50))
    ctxt(draw,2215,"3 Events Registered!",44,GREEN); ctxt(draw,2272,"Synced to Google Calendar",30,WHITE)
    ctxt(draw,2580,"Voice Scheduler",38,WHITE); ctxt(draw,2640,"Seamless Calendar Integration",30,GOLD_L)
    return img

def ss4():
    img = Image.new('RGB',(W,H),BG_TOP); draw = ImageDraw.Draw(img); bg(draw)
    ctxt(draw,180,"AI Recommends",72,WHITE); ctxt(draw,280,"Best Time Slots",72,GOLD)
    ty=480
    draw.rounded_rectangle([80,ty,W-80,ty+180], radius=20, fill=CARD)
    draw.ellipse([120,ty+60,160,ty+100], fill=RED)
    ltxt(draw,190,ty+40,"Team Meeting",46,WHITE); ltxt(draw,190,ty+105,"Duration: 60 min | High Priority",30,GOLD_L)
    ty=750; ctxt(draw,ty,"AI Recommended Times",42,GOLD_L); ty+=80
    for time,reason,stars,sel in [("09:00 - 10:00 AM","Peak Focus Time","*****",True),("02:00 - 03:00 PM","Based on Your Pattern","****",False),("04:00 - 05:00 PM","Available Slot","***",False)]:
        b=(40,70,50) if sel else CARD
        draw.rounded_rectangle([80,ty,W-80,ty+200], radius=16, fill=b)
        if sel: draw.rounded_rectangle([80,ty,W-80,ty+200], radius=16, outline=GREEN, width=3)
        ltxt(draw,130,ty+30,time,40,WHITE); ltxt(draw,130,ty+90,reason,30,GOLD_L); ltxt(draw,130,ty+140,stars,34,GOLD)
        if sel:
            draw.rounded_rectangle([W-180,ty+70,W-120,ty+120], radius=10, fill=GREEN)
            ltxt(draw,W-163,ty+73,"V",36,WHITE)
        ty+=240
    ty=1550; ctxt(draw,ty,"Today's Schedule",42,WHITE); ty+=70
    for t,ev in [("08:00",""),("09:00","Team Meeting"),("10:00",""),("11:00",""),("12:00","Lunch"),("01:00",""),("02:00","Report"),("03:00",""),("04:00",""),("05:00",""),("06:00",""),("07:00","Gym")]:
        draw.line([(130,ty+5),(W-130,ty+5)], fill=(60,70,100), width=1)
        ltxt(draw,130,ty-10,t,24,WHITE)
        if ev:
            ec=RED if ev=="Team Meeting" else ORANGE if ev in["Report","Lunch"] else GREEN
            draw.rounded_rectangle([280,ty-12,280+len(ev)*18,ty+22], radius=8, fill=ec)
            ltxt(draw,290,ty-8,ev,24,WHITE)
        ty+=55
    ctxt(draw,2580,"Voice Scheduler",38,WHITE); ctxt(draw,2640,"Smart AI Scheduling",30,GOLD_L)
    return img

def ss5():
    img = Image.new('RGB',(W,H),BG_TOP); draw = ImageDraw.Draw(img); bg(draw)
    ctxt(draw,180,"Speak in",72,WHITE); ctxt(draw,280,"Any Language",72,GOLD)
    ty=500
    for flag,lang,ex in [("US","English",'"Meeting tomorrow at 3pm"'),("KR","Korean",'"Tomorrow 3PM meeting"'),("JP","Japanese",'"Tomorrow 3PM conference"'),("CN","Chinese",'"Tomorrow 3PM meeting"'),("ES","Spanish",'"Meeting tomorrow at 3pm"'),("IN","Hindi",'"Tomorrow 3PM meeting"')]:
        draw.rounded_rectangle([80,ty,W-80,ty+200], radius=20, fill=CARD)
        draw.ellipse([120,ty+50,200,ty+130], fill=(50,60,90))
        ltxt(draw,140,ty+70,flag,40,GOLD)
        ltxt(draw,230,ty+45,lang,42,WHITE); ltxt(draw,230,ty+110,ex,30,GOLD_L)
        ltxt(draw,W-150,ty+75,"->",40,GOLD)
        ty+=240
    draw.rounded_rectangle([150,ty+20,W-150,ty+220], radius=20, fill=(30,70,50))
    draw.rounded_rectangle([150,ty+20,W-150,ty+220], radius=20, outline=GREEN, width=2)
    ctxt(draw,ty+50,"Same Result",44,GREEN)
    ctxt(draw,ty+115,"AI understands all languages",34,WHITE)
    ctxt(draw,ty+165,"Supports 6 languages",28,GOLD_L)
    ctxt(draw,2580,"Voice Scheduler",38,WHITE); ctxt(draw,2640,"Global AI Voice Recognition",30,GOLD_L)
    return img

if __name__=="__main__":
    out="AppStore/screenshots"; os.makedirs(out,exist_ok=True)
    for fn,gen in [("01_voice_input.png",ss1),("02_ai_analysis.png",ss2),("03_calendar.png",ss3),("04_smart_time.png",ss4),("05_multilingual.png",ss5)]:
        print(f"  Generating {fn}...")
        gen().save(os.path.join(out,fn),'PNG')
        print(f"  Done {fn}")
    print("All 5 screenshots done!")
