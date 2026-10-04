# Прошивка ядра ReSukiSu на Infinity-X (beyond1lte и другие exynos9820)

Ядро из ветки `resukisu-qpr2`: **Linux 4.14.356** + **ReSukiSu** (SUSFS inline hook) вместо
KernelSU-Next. Поддерживаются все 9 девайсов на Exynos 9820:
`beyond0lte`, `beyond1lte`, `beyond2lte`, `beyondx`, `d1`, `d1x`, `d2s`, `d2x`, `f62`.

Ниже — инструкция для **beyond1lte (SM-G975F)**. Для остальных всё то же самое, меняется
только кодовое имя устройства.

---

## 0. Сначала соберите ядро

Готового zip в репозитории нет. Соберите через CI (см. [`BUILD.md`](BUILD.md)) — на выходе
получится файл вида:

```
FrEeRuNnErKeRnEl-beyond1lte-v3.8-R2-ReSukiSu-AnyKernel3.zip
```

Это AnyKernel3-архив: обычный recovery-флешабле zip, который можно поставить и из TWRP,
и через `adb sideload`.

> Проверено, что сам ReSukiSu с этим ядром собирается и все его хук-гейты проходят
> ([прогон CI](https://github.com/timaa130704/android_kernel_samsung_exynos9820/actions/runs/37208641381)).
> Но полная сборка ядра и его запуск на устройстве ещё не проверены — отсюда все
> предосторожности ниже. Сначала прошейте и убедитесь, что телефон грузится.

## 1. Что понадобится

| Что | Зачем | Где взять |
|---|---|---|
| **TWRP** для вашего девайса | прошивка ядра | twrp.me, либо раздел Recovery в [Infinity-X Wiki](https://wiki.infiny-x.com) |
| **ADB + platform-tools** | `adb sideload` | [developer.android.com/tools/releases/platform-tools](https://developer.android.com/tools/releases/platform-tools) |
| **Бэкап** | откат | см. п. 2 |

> ⚠️ Держите заряженным телефон, кабель — оригинальный или хороший USB-C, компьютер — настольный
> (не виртуалка без USB passthrough).

## 2. Бэкап (обязательно)

Перед прошивкой:

1. **Сделайте бэкап через TWRP** — `Backup → Select Storage → Data (если нужно) + Boot + EFS`.
   **EFS обязателен** — это калибровка модема, потеря = потеря сети (IMEI).
2. **Сохраните оригинальный `boot.img`** из стоковой прошивки. Это ваш способ отката:
   ```
   # на телефоне в TWRP:
   dd if=/dev/block/bootdevice/by-name/boot_a of=/sdcard/boot-stock.img
   dd if=/dev/block/bootdevice/by-name/boot_b of=/sdcard/boot-stock-b.img
   ```
   Файлы заберёте через `adb pull /sdcard/boot-stock.img ./`.
3. Запишите текущую версию прошивки: `Settings → About phone → Software information`.

**Потеря EFS = потеря IMEI и сети.** Это самая частая беда при экспериментах с этими
смартфонами.

## 3. Прошивка — способ 1: через TWRP (рекомендуется)

1. Выключите телефон, зажмите **Питание + Громкость вниз** → **Recovery**.
2. В TWRP: `Wipe → Advanced Wipe` → выберите **Cache** (и **Dalvik/ART**, если есть).
   **Не трогайте** Data, System, EFS.
3. `Advanced → Install` → выберите `FrEeRuNnErKeRnEl-beyond1lte-...-AnyKernel3.zip` →
   свайп для подтверждения.
4. Дождитесь зелёной галочки и `Reboot → System`.

Установка через TWRP занимает 5–15 секунд — AnyKernel сам распаковывает `boot.img`,
подменяет ядро, собирает обратно и патчит `vbmeta`.

## 4. Прошивка — способ 2: `adb sideload`

Если не хочется копировать zip на телефон или нет карты — можно прямо с компьютера.

1. На компьютере подключите телефон по USB, телефон — **в recovery** (TWRP).
2. В TWRP включите sideload-режим: `Advanced → ADB Sideload` (в некоторых сборках —
   `Advanced → Enable ADB sideload`). TWRP покажет экран ожидания файла.
3. На компьютере:

   **Windows (PowerShell):**
   ```powershell
   adb kill-server
   adb sideload .\FrEeRuNnErKeRnEl-beyond1lte-v3.8-R2-ReSukiSu-AnyKernel3.zip
   ```

   **Linux / macOS:**
   ```bash
   adb kill-server
   adb sideload FrEeRuNnErKeRnEl-beyond1lte-v3.8-R2-ReSukiSu-AnyKernel3.zip
   ```

4. Успех выглядит так:
   ```
   adb sideload: 1 file pushed, 0 skipped. (100% pushed, ...)
   ```
   Ненулевой exit code — прошивка не пошла, смотри п. 8.
5. После завершения TWRP сам предложит `Reboot → System` (или сделай `adb reboot`).

### Что значит «сайдлоад» технически

`adb sideload` — это протокол OTA-загрузчика: zip передаётся на телефон блоками по USB
прямо в recovery, файловая система телефона не участвует. Поэтому не нужен ни root, ни
карта памяти, ни adb-доступ к /data. Файл может лежать где угодно на ПК.

Требования: recovery должен быть запущен, sideload должен быть включён в нём, и на ПК
должен быть свежий `adb`.

## 5. Проверка, что ядро встало

После загрузки:

1. **Версия ядра** — должно содержать ваш `CONFIG_LOCALVERSION`:
   ```bash
   adb shell uname -a
   ```
   Ожидаемый вид: `... 4.14.356-⚡ FrEeRuNnErKeRnEl-v3.8-R2 ⚡ ...` (⚡ может отображаться
   как `=` или `-`, зависит от шрифта/локали).

2. **ReSukiSu в dmesg** (нужен root или `adb shell dmesg | grep -i resukisu` с разрешениями):
   ```bash
   adb shell su -c 'dmesg | grep -iE "resukisu|susfs|kernelsu"'
   ```
   Должны быть строки вида `-- ReSukiSU version code: ...` и `susfs is initialized! version: v2.3.0`.

3. Откройте **KSU Toolkit / менеджер** — если статус «Работает» и версия ядра совпадает,
   всё в порядке.

## 6. Установка менеджера ReSukiSu

Само ядро не даёт интерфейс. Нужен APK-менеджер:

- **ReSukiSu Manager** — [релизы](https://github.com/ReSukiSU/ReSukiSU/releases) (рекомендуется);
- либо совместимый: официальный KernelSU, RKSU, MKSU, SukiSU-Ultra (ReSukiSu умеет работать
  с несколькими менеджерами сразу).

Установка APK **после** прошивки ядра. Если менеджер пишет « kernelsu not installed» — ядро
не сматчилось, вернитесь в TWRP и перепрошейте zip.

Модули ( metamodules ) ставятся из менеджера поверх — работать будут, но помните, что это
Suki/KernelSU-модули, а не Magisk-модули. Magisk-модули из Magisk в этой связке
не поддерживаются.

## 7. Откат

Способ 1 — **прошить стоковый `boot.img`** в TWRP:
```bash
adb push boot-stock.img /sdcard/
# TWRP: Advanced → Install → boot-stock.img
```
Либо прямо с ПК через `adb sideload boot-stock.zip` (нужно запаковать img в zip с
META-INF, проще через TWRP).

Способ 2 — **полная прошивка стоковой прошивки через Odin** (файл `AP_*.tar.md5` из того
же релиза, что и была установлена). Это надёжнее: восстанавливает все разделы, включая
EFS-бэкап.

Способ 3 — если телефон не грузится: загрузитесь в Download Mode
(**Питание + Громкость вниз + Домашняя**), подключите к Odin, прошейте стоковую прошивку.

## 8. Если что-то пошло не так

| Симптом | Причина | Что делать |
|---|---|---|
| Телефон завис на загрузке (bootloop) | ядро не совместимо с прошивкой | Откат (п. 7), загрузка в Safe Mode (см. ниже) |
| Чёрный экран, нет логотипа | не та `IS_SLOT_DEVICE` | Пересоберите zip с `--slot 0`, либо прошейте стоковый boot (п. 7) |
| `adb sideload` зависает / `sideload: error` | не включён sideload в TWRP | `Advanced → ADB Sideload`, затем `adb kill-server` и повторить. Смените кабель/порт |
| `adb: no devices` | телефон не в recovery, или adb не видит recovery | `adb kill-server`; попробуйте другой USB-порт, отключите хабы, используйте порт **задней** панели |
| Телефон стартует со старым ядром | загрузка идёт с другого слота | Проверьте `uname -a`. Прошейте zip ещё раз; убедитесь, что A/B слот активный тот же |
| Нет сети / пропал IMEI | сломан EFS | Восстановите EFS из бэкапа — **ничего не восстановить без него** |
| Банковские приложения не работают | детект root | ReSukiSu: менеджер → настройки → включить скрытие root / susfs-модули |
| DRM (Widevine L1) сломался | смена ядра ломает DRM | Обычно не восстановимо без полной переустановки прошивки |

**Safe Mode** — если ядро грузится, но система не стартует:
1. Выключите телефон.
2. Зажмите **Питание** и держите, пока не появится меню «Нажмите и удерживайте Питание, чтобы
   отключить безопасный режим».
3. Подтвердите.

Safe Mode отключает сторонние модули, но **не** помогает, если не грузится само ядро.

## 9. Что именно изменилось по сравнению с обычным ядром Infinity-X

Замена root-решения влияет на следующее:

- **Менеджер.** Был KsuNext → стал ReSukiSu. Придётся ставить другой APK и переустановить
  модули заново (формат модулей общий, но состав может отличаться).
- **Модули.** Модули от Magisk работать не будут. Метамодули SukiSU/KernelSU — работают.
- **Magisk отсутствует.** Если вы пользовались Magisk-фичами (SafetyNet, DenyList, второй
  root) — их надо закрывать средствами ReSukiSu/SusFS.
- **Функции скрытия.** Включены SusFS-патчи (скрытие путей, mount, kstat, uname,
  bootconfig, hide ksu/susfs-символов из `/proc/kallsyms`) и Open Redirect.
- **Проверки детекта.** Комбинации susfs 2.3.0 + ReSukiSu на 4.14 — экспериментальная.
  Если приложение палит root, отключайте опции susfs по одной.

---

## Поддержка

Это порт ReSukiSu на 4.14, который сам проект позиционирует как «собирается руками».
См. [resukisu.org](https://resukisu.org) и
[ReSukiSU/ReSukiSU](https://github.com/ReSukiSU/ReSukiSU).