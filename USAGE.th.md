# การใช้งาน PC Tunes

คู่มือนี้ครอบคลุมทุกอย่างที่ PC Tunes ทำได้หลังติดตั้งเสร็จ ถ้ายังไม่ได้ build และโหลด
extension ให้เริ่มที่ [INSTALL.th.md](INSTALL.th.md) ก่อน

*(English version: [USAGE.md](USAGE.md))*

PC Tunes ควบคุม YouTube Music ที่กำลังเล่นอยู่ใน Chromium browser ของคุณ — จะเป็น web app
ที่ติดตั้งไว้ หรือแท็บธรรมดาก็ได้ ตัวแอปไม่ได้เล่นเสียงเอง แต่ "อ่านและสั่ง" หน้าเว็บนั้น
ดังนั้นไม่มีอะไรต้อง "เปิด" นอกจากมี YouTube Music เล่นอยู่ที่ไหนสักที่ หรือให้ PC Tunes
เริ่มให้ (ดู [Cold start](#cold-start))

## ไอคอนบน menu bar

PC Tunes อยู่บน menu bar ไม่มีไอคอนใน Dock และไม่มีหน้าต่างหลัก คลิกที่ไอคอนเพื่อเปิด
dropdown คลิกที่อื่นเพื่อปิด

ปกติไอคอนจะแสดงเดี่ยวๆ ถ้าเปิด **Show track title beside the icon** ใน Settings ชื่อเพลง
ปัจจุบันจะโผล่ข้างไอคอน ตัดความยาวตามที่ตั้งไว้

## Dropdown

ทุกอย่างอยู่ใน dropdown ที่เปิดจากไอคอน menu bar

- **Artwork, ชื่อเพลง, ศิลปิน, อัลบั้ม** — **artwork** และ **ชื่อเพลง** เป็นปุ่ม คลิกอันไหน
  ก็ได้เพื่อเปิด YouTube Music web app ใน browser โดยโฟกัสที่เพลงที่กำลังเล่น
- **Song / Video badge** — badge เล็กๆ ข้างชื่อศิลปินบอกว่าเพลงปัจจุบันเล่นแบบ *Song* หรือ
  *Video* จะไม่มี badge เมื่อหน้าเว็บไม่ได้บอก (ทุกหน้าที่ไม่ใช่หน้า watch) ดู
  [Song กับ Video](#song-กับ-video)
- **Like / dislike** — ปุ่มโป้งขึ้น/ลงทางขวาสะท้อน rating ของ YouTube Music เอง และตั้งค่า
  เมื่อคุณคลิก
- **Progress bar** — แสดงเวลาที่ผ่านไปและเวลารวม ลากปุ่มเพื่อ seek
- **ปุ่มควบคุมการเล่น** เรียงซ้ายไปขวา:
  - **Shuffle** — สลับ shuffle ปุ่มสว่างเมื่อ shuffle เปิด
  - **Previous** — เพลงก่อนหน้า
  - **Play / Pause** — ปุ่มกลาง ไอคอนสะท้อนสถานะปัจจุบัน
  - **Next** — เพลงถัดไป
  - **Repeat** — วน repeat mode ของคิว: off → repeat all → repeat one ปุ่มสว่างเมื่อ
    repeat เปิด และแสดงไอคอน "repeat one" แบบเฉพาะสำหรับโหมดวนเพลงเดียว
- **Volume** — slider ตั้งระดับเสียงของ YouTube Music
- **Go to YouTube Music** — เปิด web app เหมือนคลิก artwork หรือชื่อเพลง
- **Settings…** — เปิดหน้าต่างตั้งค่า (ดู [Settings](#settings))
- **Quit PC Tunes** — ปิดแอป ไม่ปิด browser และไม่หยุดการเล่น

ปุ่ม shuffle, repeat, next, previous, like และ dislike จะจางและกดไม่ได้เมื่อไม่มีหน้า
YouTube Music ที่ควบคุมได้เชื่อมต่ออยู่

## Song กับ Video

YouTube Music ให้เพลงจำนวนมากทั้งแบบ song และ official music video — คนละไฟล์ ความยาว
ต่างกัน badge ใต้ชื่อเพลงบอกว่ากำลังเล่นแบบไหน

เมื่อเพลงมีทั้งสองแบบ PC Tunes จะขอ **song** จากหน้าเว็บ เพราะสองแบบเป็นคนละไฟล์ การสลับ
เลยเริ่มเพลงใหม่จากต้น — ไม่มีตำแหน่งให้ seek ไป จึงยอมรับพฤติกรรมนี้แทนที่จะแก้ หน้าเว็บ
จำ preference นี้ข้ามเพลงถัดๆ ไป และลืมเฉพาะตอน reload เพลงที่ถูกขัดจังหวะเลยมักเป็นแค่
เพลงแรกหลังเปิด web app ซึ่งเพิ่งเล่นไปไม่กี่วินาที เพลงที่ไม่มีแบบ song (อัลบั้มรวม, live
set) จะถูกปล่อยให้เล่นเป็น video ต่อไป

## Cold start

ไม่ต้องเปิด YouTube Music ก่อน กด **Play** ตอนที่ไม่มีอะไรเล่นอยู่ แล้ว PC Tunes จะเปิด
YouTube Music ไว้ข้างหลังสิ่งที่คุณกำลังดู เริ่มเล่น แล้ว minimize หน้าต่าง browser ลง Dock
เมื่อเพลงเล่นจริงแล้ว — ได้ฟังเพลงโดยไม่เสียตำแหน่งในแอปที่กำลังใช้อยู่

## Global hotkeys

Global hotkeys ให้คุมการเล่นได้โดยไม่ต้องเปิด dropdown จากแอปไหนก็ได้

**ปิดอยู่โดย default** เปิดที่ **Settings → Hotkeys → Global hotkeys** ค่าเริ่มต้นคือ:

| Action | Shortcut |
| --- | --- |
| Play / Pause | `⌃⌥Space` |
| Next | `⌃⌥→` |
| Previous | `⌃⌥←` |

แต่ละอันเปลี่ยนได้ใน Settings — คลิกช่อง shortcut แล้วกดคีย์ที่ต้องการ ถ้าคีย์ผสมนั้นถูกแอป
อื่นจับจองไว้แล้ว ระบบจะปฏิเสธ และ Settings จะบอกว่าอันนั้นใช้ไม่ได้ เปลี่ยนคีย์อันนั้น
อีกสองอันก็ยังทำงานต่อ

Hotkeys ลงทะเบียนด้วย Carbon `RegisterEventHotKey` ซึ่งต่างจากทาง `NSEvent` ที่แอปส่วนใหญ่ใช้
ตรงที่ **ไม่ต้องขอ Accessibility permission** PC Tunes ไม่เคยขอสิทธิ์นั้น

## Settings

เปิด Settings จาก dropdown ทุกอย่างบันทึกทันที

- **Launch at login** — เปิด PC Tunes อัตโนมัติเมื่อ login
- **Show track title beside the icon** — ปิดอยู่โดย default เมื่อเปิด ชื่อเพลงปัจจุบันจะแสดง
  ข้างไอคอน menu bar ตัดตาม **Title length** (10–80 ตัวอักษร; ตัวอย่างด้านล่างแสดงว่าชื่อ
  ยาวๆ จะออกมาแบบไหน)
- **Show notifications when the track changes** — ปิดอยู่โดย default เมื่อเปิด จะมี
  notification ของ macOS เด้งทุกครั้งที่เปลี่ยนเพลง
- **Global hotkeys** — ปิดอยู่โดย default; ดู [Global hotkeys](#global-hotkeys)

## เมื่อปุ่มใดปุ่มหนึ่งใช้ไม่ได้

ทุกอย่างที่ PC Tunes สั่งพึ่งพา selector เข้าไปในโครงสร้าง HTML ของ YouTube Music ซึ่ง
Google เปลี่ยนได้โดยไม่แจ้ง เมื่ออันไหนพัง ปุ่มที่มันคุมจะหยุดทำงาน และ PC Tunes จะแสดง
**notice** สั้นๆ ที่ด้านบนของ dropdown แทนที่จะเงียบไปเฉยๆ

ถ้าเกิดขึ้น ลอง reload browser extension มักกลับมาใช้ได้ระหว่างที่รอแก้ selector ดูหมวด
[Troubleshooting](INSTALL.th.md#ถ้าทำแล้วไม่ได้ผล) ใน install guide และ
[Known limitations](README.md#status-and-known-limitations) ใน README สำหรับภาพรวม
