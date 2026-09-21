# การติดตั้ง PC Tunes

คู่มือนี้เขียนสำหรับคนที่ไม่เคย build โปรเจกต์ Swift มาก่อน ถ้าติดปัญหาระหว่างทาง
ให้ดูหัวข้อ [ถ้าทำแล้วไม่ได้ผล](#ถ้าทำแล้วไม่ได้ผล) ท้ายเอกสาร ซึ่งจัดตามอาการที่เห็นจริงบนหน้าจอ

*(English version: [INSTALL.md](INSTALL.md))*

## สิ่งที่ต้องมี

- **macOS 14 ขึ้นไป**
- **Google Chrome หรือเบราว์เซอร์ตระกูล Chromium อื่น** (Brave, Edge) — Chrome
  คือตัวเดียวที่ทดสอบจริง ดูรายละเอียดของ Brave/Edge ได้ในหัวข้อ
  [Known limitations](README.md#status-and-known-limitations) ของ README
- **Xcode Command Line Tools** — ไม่จำเป็นต้องลง Xcode เต็มตัว ถ้าไม่แน่ใจว่ามีอยู่แล้วหรือยัง
  เปิด Terminal แล้วรัน:

  ```bash
  xcode-select --install
  ```

  ถ้ามีอยู่แล้ว คำสั่งนี้จะแจ้งเฉยๆ แล้วจบการทำงาน ถ้ายังไม่มี จะเปิดตัวติดตั้งเล็กๆ ขึ้นมา
  รอให้ติดตั้งเสร็จก่อนไปขั้นตอนถัดไป

## 1. Clone repository

```bash
git clone https://github.com/PCInfiniteSoft/pc-tunes.git
cd pc-tunes
```

(แทน URL ด้วยที่อยู่จริงของ repository นี้)

## 2. Build แอป

```bash
cd app
./build.sh
```

สคริปต์นี้จะรัน `swift build -c release`, ประกอบ `PC Tunes.app` ขึ้นมาเอง (โปรเจกต์นี้ไม่มีไฟล์
Xcode project) แล้วเซ็น ad-hoc signature ให้ — ขั้นตอนเซ็นนี้จำเป็นตอนแอปพยายามลงทะเบียนตัวเองเป็น
login item การ build ครั้งแรกจะ compile ทุกอย่างใหม่หมด ใช้เวลาไม่ถึงนาที แล้วจะเห็นผลลัพธ์แบบนี้:

```
Building for production...
...
Build of product 'PCTunes' complete!
PC Tunes.app: replacing existing signature
Built /path/to/pc-tunes/app/PC Tunes.app
```

ถ้าเจอ error แทนที่จะเป็นแบบนี้ ส่วนใหญ่มักเกิดจากยังไม่ได้ลง Command Line Tools —
ย้อนกลับไปดูหัวข้อ "สิ่งที่ต้องมี" ด้านบน

## 3. เปิดแอป

รันตรงจากตำแหน่งที่ build เสร็จได้เลย:

```bash
open "PC Tunes.app"
```

หรือจะลาก `PC Tunes.app` ไปไว้ใน `/Applications` ก่อนแล้วค่อยเปิดจากที่นั่นก็ได้ — ได้ผลเหมือนกัน
ไม่มีตัวติดตั้ง (installer) และไม่มีอะไรอื่นต้องวางไว้ในเครื่อง

ตอนนี้แอปจะยังไม่มีไอคอนใน Dock หรือข้อความใน menu bar — มันเป็นแอปแบบ menu-bar-only
(มองหาไอคอนรูปสามเหลี่ยม play วงกลมเล็กๆ ใกล้นาฬิกา) เป็นเรื่องปกติจนกว่าจะทำขั้นตอนที่ 4 เสร็จ
เพราะถ้ายังไม่มี extension แอปก็ไม่มีอะไรจะแสดง

## 4. โหลด browser extension

1. เปิด `chrome://extensions` ใน Chrome
2. เปิดสวิตช์ **Developer mode** (มุมขวาบน)
3. คลิก **Load unpacked**
4. เลือกโฟลเดอร์ `extension/` ที่อยู่ใน repository ที่ clone มา (เลือกที่ตัวโฟลเดอร์เอง
   ไม่ใช่ไฟล์ข้างในโฟลเดอร์)

ควรเห็น "PC Tunes Bridge" ปรากฏในรายการ extension

## 5. ตรวจสอบว่าใช้งานได้จริง

1. เปิด YouTube Music (`music.youtube.com`) ใน Chrome แล้วเล่นเพลงสักเพลง
2. คลิกไอคอน PC Tunes ใน menu bar ภายในไม่กี่วินาทีควรเห็นชื่อเพลง ศิลปิน และปกอัลบั้ม
   พร้อมทั้งปุ่มควบคุมต่างๆ ใช้งานได้ (ไม่ถูก disable)
3. ลองกด play/pause จาก dropdown แล้วเช็กว่าการเล่นเพลงบนหน้าเว็บสลับสถานะจริง

### เช็กลิสต์รันครั้งแรก

- [ ] `./build.sh` รันจบโดยไม่มี error และพิมพ์ "Built .../PC Tunes.app"
- [ ] `PC Tunes.app` กำลังทำงานอยู่ (เห็นไอคอนใน menu bar)
- [ ] "PC Tunes Bridge" ปรากฏและเปิดใช้งานอยู่ที่ `chrome://extensions`
- [ ] เปิด YouTube Music แล้วเล่นเพลงอยู่ dropdown แสดงเพลงปัจจุบัน
- [ ] Play/pause, next, previous ใช้งานได้จาก dropdown
- [ ] (ถ้าต้องการ) เปิด "Launch at login" จาก dropdown เพื่อให้ PC Tunes เปิดเองตอน login

## ถ้าทำแล้วไม่ได้ผล

**Dropdown ขึ้นข้อความ "Extension not connected"**
แอปทำงานอยู่แต่ยังไม่มีเบราว์เซอร์ไหนเชื่อมต่อมาหา ลอง reload แท็บ YouTube Music
(extension จะเริ่มเชื่อมต่อก็ต่อเมื่อ content script ของมันรันบนหน้าที่ตรงเงื่อนไขเท่านั้น)
แล้วเช็ก log ของ extension เอง: ที่ `chrome://extensions` คลิก "service worker" ใต้
PC Tunes Bridge เพื่อเปิด console ของมัน มองหาบรรทัด
`[PC Tunes] connected on port 8787` — ถ้าเจอ
`[PC Tunes] no greeting on port 8787 — not our server` แทน แปลว่ามีอย่างอื่นครอง port
นั้นอยู่ และ extension กำลังไล่สแกนต่อในช่วง 8787–8791 รอสักครู่ ถ้าไม่เห็นอะไรเลยในนั้น
ให้เช็กว่า extension เปิดใช้งานอยู่จริง และกำลังอยู่บน `music.youtube.com` จริงๆ

**ไม่มีอะไรปรากฏใน menu bar เลย**
แอปอาจไม่ได้ทำงาน หรือปิดตัวเองไปทันทีหลังเปิด เช็ก Console.app (ค้นหรือ filter คำว่า
"PC Tunes") ดูว่ามี crash หรือบรรทัดประมาณ `could not bind a port in 8787-8791` หรือไม่
— ข้อความนี้แปลว่าทุก port ในช่วงนั้นถูกใช้งานโดยอย่างอื่นอยู่แล้ว ให้ปิดโปรแกรมนั้น
(หรือ PC Tunes อีกชุดที่ค้างอยู่) แล้วเปิดใหม่ ถ้า Console.app ไม่มีอะไรขึ้นเลย
ให้ลองรัน `./build.sh` จาก terminal อีกครั้งแล้วอ่าน output ตรงๆ แทนการดับเบิลคลิกเปิดแอป

**ปุ่มต่างๆ มองเห็นแต่กดแล้วไม่มีอะไรเกิดขึ้น**
extension น่าจะเชื่อมต่ออยู่ แต่ selector บนหน้าเว็บอาจไม่ตรงกับ markup ปัจจุบันแล้ว —
YouTube Music เปลี่ยน markup โดยไม่แจ้งล่วงหน้า และทุกปุ่มในนี้ทำงานด้วยการหา element
บนหน้าเว็บจริงแล้วคลิกมันแทนผู้ใช้ เปิด DevTools บนแท็บ YouTube Music เอง แล้วดู Console
หาคำเตือนแบบ `[PC Tunes] ... not found` ปัญหาเดียวกันนี้จะโผล่เป็นแถบแจ้งเตือนสีส้มใน
dropdown ของ PC Tunes ด้วย ดูหัวข้อ
[Known limitations](README.md#status-and-known-limitations) ใน README — selector ทั้งหมด
อยู่ใน `extension/inject.js` เป็นค่าคงที่ที่ตั้งชื่อไว้ชัดเจน การแก้ selector ที่เสีย
คือสิ่งที่โปรเจกต์นี้ต้องการความช่วยเหลือมากที่สุดตอนนี้
