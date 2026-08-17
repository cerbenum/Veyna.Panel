<div align="center">

<img src="logo.png" alt="VEYNA" width="110">

# VEYNA Panel

**یک دستور. سرور خودت. کاربران خودت.**

[![English](https://img.shields.io/badge/English-2a2a2a?style=for-the-badge&labelColor=1a1a1a)](README.md)
[![فارسی](https://img.shields.io/badge/%D9%81%D8%A7%D8%B1%D8%B3%DB%8C-5B5BD6?style=for-the-badge&labelColor=1a1a1a)](README.fa.md)

</div>

---

<div dir="rtl">

## نصب

</div>

```bash
curl -fsSL https://raw.githubusercontent.com/cerbenum/Veyna.Panel/main/installer/install.sh | sudo bash
```

<div dir="rtl">

دیتابیس، وب‌سرور، گواهی و خودِ نود همه خودکار نصب می‌شن.

</div>

| پیش‌نیاز | |
|---|---|
| <img src="https://img.shields.io/badge/Ubuntu-E95420?style=flat-square&logo=ubuntu&logoColor=white&labelColor=1a1a1a" height="22"> | ۲۲.۰۴ به بالا |
| <img src="https://img.shields.io/badge/Debian-A81D33?style=flat-square&logo=debian&logoColor=white&labelColor=1a1a1a" height="22"> | ۱۲ به بالا |
| <img src="https://img.shields.io/badge/Arch-2a2a2a?style=flat-square&logo=linux&logoColor=white&labelColor=1a1a1a" height="22"> | x86_64 |

---

<div dir="rtl">

## بعد از نصب

نصاب آدرس پنل و مسیر ادمین رو چاپ می‌کنه. بازش کن و وارد شو.

</div>

```bash
sudo veyna-panelctl info      # آدرس پنل
sudo veyna-panelctl status    # وضعیت اجرا
sudo veyna-panelctl health    # سلامت سرویس
```

<div dir="rtl">

## نصب بدون تعامل

</div>

```bash
curl -fsSL https://raw.githubusercontent.com/cerbenum/Veyna.Panel/main/installer/install.sh -o install.sh
sudo bash install.sh -y \
  --domain panel.example.com \
  --admin-user admin \
  --admin-pass 'ChangeThis123!'
```

<div dir="rtl">

دستور `sudo bash install.sh --help` همهٔ گزینه‌ها رو نشون می‌ده.

## به‌روزرسانی

نصاب رو دوباره اجرا کن. مسیر ادمین، کلید رمزنگاری و رمز دیتابیس دقیقاً دست‌نخورده می‌مونن.

</div>

---

<div align="center">

<sub>برنامهٔ کلاینت</sub>

[![VEYNA App](https://img.shields.io/badge/VEYNA-App-5B5BD6?style=for-the-badge&labelColor=1a1a1a)](https://github.com/cerbenum/Veyna.App)

<br>

<sub>اختصاصی — [LICENSE](LICENSE) را ببینید. این مخزن فقط نصاب را منتشر می‌کند؛ سورس بسته است.</sub>

<br>

**Cerbenum**

</div>
