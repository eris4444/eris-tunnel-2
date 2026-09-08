<div dir="rtl">

# ERIS TUNNEL 2

**🌐 Language / زبان**
[English](README.md) • [**فارسی**](README.fa.md)

</div>

```
╭────────────────────────────────────────────────────────────────╮
│ ███████╗██████╗ ██╗ ███████╗                                   │
│ ██╔════╝██╔══██╗██║ ██╔════╝                                   │
│ █████╗  ██████╔╝██║ ███████╗                                   │
│ ██╔══╝  ██╔══██╗██║ ╚════██║                                   │
│ ███████╗██║  ██║██║ ███████║                                   │
│ ╚══════╝╚═╝  ╚═╝╚═╝ ╚══════╝                                   │
│ T U N N E L  2   ·   backhaul reverse tunnel                   │
╰────────────────────────────────────────────────────────────────╯
```

<div dir="rtl">

**مدیر پیشرفته تانل معکوس Backhaul**
`نسخه 1.0.2`
پشتیبانی: `@erisrttg`

---

## معرفی

**Eris Tunnel 2** یک اسکریپت Bash برای نصب، ساخت، مدیریت، مانیتورینگ، تست و عیب‌یابی تانل‌های معکوس مبتنی بر **Musixal/Backhaul** است.

> **ایران = سرور (Server)**
> **خارج = کلاینت (Client)**
> پیرکد روی سرور ایران ساخته می‌شود و روی سرور خارج پیست می‌شود.

## نصب سریع

</div>

```
curl -fsSL https://raw.githubusercontent.com/eris4444/eris-tunnel-2/main/install.sh | bash
```

<div dir="rtl">

سپس برای اجرا:

</div>

```
eristun2
```

<div dir="rtl">

## معماری

</div>

```
USER
  │
  ▼
┌──────────────────────┐
│      IRAN SERVER     │
│   Backhaul Server    │
│   User-facing Ports  │
└──────────┬───────────┘
           │ Reverse Tunnel
           ▼
┌──────────────────────┐
│     KHAREJ SERVER    │
│   Backhaul Client    │
│ Xray / Panel / Apps  │
└──────────────────────┘
```

<div dir="rtl">

## امکانات اصلی

- ساخت مرحله‌به‌مرحله تانل ایران و خارج
- پیرکد نسخه ۲، با سازگاری کامل با پیرکدهای قدیمی B1
- فوروارد چندپورتی و نگاشت دلخواه مقصد
- ترنسپورت‌ها: `tcp`، `tcpmux`، `ws`، `wsmux`، `wss`، `wssmux`، `udp`
- پروفایل‌های عملکرد: Stable، Balanced، Low Ping، Turbo
- داشبورد زنده و بررسی اتصالات در سطح کرنل
- تست تأخیر و پهنای باند، هم غیرفعال و هم فعال
- مدیریت گواهی TLS با Let's Encrypt از طریق `acme.sh`
- سرویس systemd، اجرای خودکار در بوت و ری‌استارت زمان‌بندی‌شده
- به‌روزرسانی خودکار هسته و خود اسکریپت

<details>
<summary><b>فهرست کامل امکانات</b></summary>

- تنظیمات پیشرفته و پین کردن مقادیر
- مدیریت اندپوینت
- شمارش ترافیک
- لاگ زنده، خطاها و خلاصه رویدادها
- تحلیل الگوی قطعی و اتصال مجدد
- پاسخ‌دهنده تست سرعت روی سرور خارج
- بررسی سلامت و تست لینک
- مقایسه اثر انگشت کانفیگ دو سرور
- تست دسترسی به سرور ایران
- شناسایی خودکار گواهی
- گواهی self-signed و ورود دستی مسیر
- پایش تاریخ انقضای گواهی
- پاکسازی تانل‌های ناقص
- توقف امن سرویس و kill اجباری
- بازتولید خودکار کانفیگ
- ویرایش دستی کانفیگ
- تولید توکن تصادفی
- تشخیص IP و NAT
- بررسی تداخل پورت
- نصب‌کننده وابستگی‌ها
- منبع به‌روزرسانی دلخواه
- نصب به‌صورت دستور `eristun2`
- حذف کامل

</details>

## پروفایل‌های عملکرد

| پروفایل  | مناسب برای                        |
| -------- | --------------------------------- |
| Stable   | مسیرهای پرافت و ناپایدار          |
| Balanced | استفاده عمومی                     |
| Low Ping | گیم و ترافیک حساس به تأخیر        |
| Turbo    | تعداد کاربر و کانکشن بالا         |

## منوی تانل

صفحه هر تانل بر اساس کاری که هر گزینه انجام می‌دهد گروه‌بندی شده است. گزینه
`Pair code` فقط سمت ایران نمایش داده می‌شود، چون تنها همان سمت پیرکد می‌سازد.

</div>

```
CONTROL     1 Start        2 Stop       3 Restart
PAIRING     p Pair code                              (فقط ایران)
CONFIGURE   4 Ports        5 Tuning     6 Endpoint    7 Scheduled restart
INSPECT     8 Show config  s Speed test L Logs + connections
ADVANCED    e Edit config by hand       d Delete tunnel
```

<div dir="rtl">

## عیب‌یابی

</div>

```
Live Log
Last 60 Lines
Health Check
Link Test
Config Fingerprint
Reach Iran Server
Speed Responder
Toggle Debug Logs
```

<div dir="rtl">

## مدیریت هسته

</div>

```
Latest GitHub Release
Local files from /root/backhaul
Custom URL
```

<div dir="rtl">

معماری‌های پشتیبانی‌شده:

</div>

```
amd64
arm64
arm
386
```

<div dir="rtl">

هش SHA-256 هر باینری دانلودشده پیش از نصب نمایش داده می‌شود. آدرس دلخواه
حتماً باید HTTPS باشد و پیش از نصب تأیید صریح گرفته می‌شود.

## امنیت

تمام سخت‌سازی‌های مسیرهای ورود داده از بیرون سرور در این نسخه حفظ شده است:

- پیرکد پیش از استفاده به‌طور کامل اعتبارسنجی می‌شود. توکن فقط می‌تواند شامل
  `A-Z a-z 0-9 + / = . _ @ : -` باشد و نگاشت پورت‌ها فقط رقم و جداکننده. در
  نتیجه یک پیرکد دستکاری‌شده نمی‌تواند کاراکترهای خطرناک شل را وارد سرور کند.
- فایل `meta.conf` دیگر توسط شل `source` نمی‌شود؛ به‌جای آن به‌عنوان داده و
  بر اساس فهرست سفید کلیدهای شناخته‌شده خوانده می‌شود.
- اعتبارسنجی IPv4 و دامنه، مقادیر خارج از بازه و دامنه‌هایی که با `-` شروع
  می‌شوند را رد می‌کند.
- تمام فایل‌های موقت با `mktemp` ساخته می‌شوند و هیچ مسیر قابل حدس زدنی زیر
  `/tmp` باقی نمانده است.


## منبع به‌روزرسانی

</div>

```
https://raw.githubusercontent.com/eris4444/eris-tunnel-2/main/eris-tunnel-2.sh
```

<div dir="rtl">

## مسیرهای روی سرور

</div>

```
/etc/eris-tunnel-2/
/etc/eris-tunnel-2/tunnels/
/etc/eris-tunnel-2/certs/
/usr/local/bin/backhaul
/usr/local/bin/eristun2
```

<div dir="rtl">

## مهاجرت از نصب قبلی

مسیر داده‌ها عوض شده، پس تانل‌های قبلی خودبه‌خود شناسایی نمی‌شوند:

</div>

```
systemctl stop 'backhaul@*'
cp -a /etc/dark-backhaul /etc/eris-tunnel-2
systemctl start 'backhaul@*'
```

<div dir="rtl">

کانفیگ تانل‌ها، فایل‌های `meta.conf` و پیرکدهای B1/B2 بدون تغییر کار می‌کنند.

## هسته

هسته تانل از پروژه **Musixal/Backhaul** می‌آید. Eris Tunnel 2 یک لایه
مدیریتی مستقل است که بر پایه پروژه MIT با نام **darktunnelmika/dark-backhaul**
ساخته شده و وابستگی رسمی به هیچ‌کدام از پروژه‌های بالادست ندارد.

## نسخه و پشتیبانی

</div>

```
Eris Tunnel 2
Version: 1.0.2
Support: @erisrttg
```

<div dir="rtl">

**🌐 Language / زبان**
[English](README.md) • [**فارسی**](README.fa.md)

</div>
