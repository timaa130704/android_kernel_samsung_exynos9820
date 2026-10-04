# Сборка ядра

Интерактивный `build.sh` в корне репозитория рассчитан на ручной запуск на машине
автора (захардкоженный путь `~/Android/ToolChain/ZyClang-23`, диалоги `read -p`,
создание GitHub-релиза). Для CI он не годится — поэтому есть
[`ci/build-kernel.sh`](ci/build-kernel.sh), который делает одну устройство, одним проходом,
без вопросов.

## Запуск вручную

```bash
git clone --recursive https://github.com/timaa130704/android_kernel_samsung_exynos9820.git
cd android_kernel_samsung_exynos9820
git checkout resukisu-qpr2

# полная сборка: Image + AnyKernel3 zip
./ci/build-kernel.sh --device beyond1lte --mode full

# быстрая проверка: собрать только ReSukiSU
./ci/build-kernel.sh --device beyond1lte --mode verify
```

Тулчейн подтягивается автоматически и кэшируется в `~/.cache/kernel-toolchain`. По умолчанию
это AOSP `clang-r450784d` — **clang 14.0.6**, ближайший из ещё опубликованных к тому,
что просит само дерево (`build.config.universal9820`: `CLANG_VERSION=clang-4691093`,
то есть clang 12; эти пребилты AOSP уже удалил). Чтобы использовать свой:

```bash
CLANG_DIR=/path/to/clang ./ci/build-kernel.sh --device beyond1lte
```

> Скрипт **всегда** предпочитает закреплённый тулчейн системному `clang` из `PATH`.
> На GitHub-hosted в образе лежит clang 18, а дерево 4.14 на нём не собирается —
> использовать системный clang можно только осознанно, через `ALLOW_SYSTEM_CLANG=1`.

### Ключи

| Ключ | Значение |
|---|---|
| `--device` | кодовое имя: `beyond0lte`, `beyond1lte`, `beyond2lte`, `beyondx`, `d1`, `d1x`, `d2s`, `d2x`, `f62` |
| `--mode` | `full` (Image + zip) или `verify` (только ReSukiSu) |
| `--slot` | `IS_SLOT_DEVICE` в AnyKernel. `1` — A/B (верно для beyond1lte), `0` — single-slot |
| `--out` | каталог для сборки (по умолчанию `out/`) |
| `--toolchain-url` | свой URL тулчейна |

Результат полной сборки: `out/packages/FrEeRuNnErKeRnEl-<device>-<ver>-ReSukiSu-AnyKernel3.zip`.
Как его прошить — в [`FLASHING.md`](FLASHING.md).

## Статус проверки

Прогон `mode: verify`, девайс `beyond1lte`, GitHub-hosted — **успешно** (3 мин 42 с):
<https://github.com/timaa130704/android_kernel_samsung_exynos9820/actions/runs/37208641381>

```
-- ReSukiSU version code: 30701
-- KERNEL_VERSION: 4.14
-- KERNEL_TYPE: Non-GKI
-- ReSukiSU: using SuSFS Inline hook
-- ReSukiSU/susfs_inline: ksu_handle_setresuid found
-- ReSukiSU/susfs_inline: ksu_handle_execveat found
-- ReSukiSU/susfs_inline: ksu_handle_faccessat found
-- ReSukiSU/susfs_inline: ksu_handle_sys_read found
-- ReSukiSU/susfs_inline: ksu_handle_stat found
-- ReSukiSU/susfs_inline: ksu_handle_sys_reboot found
-- ReSukiSU/susfs_inline: ksu_handle_input_handle_event found
```

То есть все хук-гейты ReSukiSu прошли, а весь код `drivers/kernelsu/` собрался
(21 объект, включая `core/`, `policy/`, `feature/`, `hook/`, `infra/`, `runtime/`,
`selinux/`, `sulog/`, `supercall/`) тулчейном clang 14 поверх ядра 4.14.

**Что этим НЕ проверено:** линковка всего ядра и работоспособность на устройстве.
Для этого нужен `mode: full` — то есть self-hosted runner.

## Два режима и зачем они разные

**`verify`** — конфигурирует ядро, делает `modules_prepare` и собирает **только
`drivers/kernelsu/`**. Полное ядро не линкуется. При этом ReSukiSu прогоняет свои
Kbuild-проверки (`tools/inline_hook_check.mk`, `tools/susfs_compat.mk`), которые валят
сборку на любом отсутствующем или лишнем хуке. Это ровно то место, где ломается порт на
4.14 — ради него `verify` и существует.

Время: ~15 минут. Место: ~6 ГБ. RAM: ~8 ГБ.

**`full`** — полная сборка ядра и упаковка AnyKernel3. Нужно ~40 ГБ свободного места и
несколько часов CPU (на 4 ядрах — ориентировочно 4–8 часов).

## GitHub Actions

Workflow: [`.github/workflows/kernel.yml`](../.github/workflows/kernel.yml).
Только ручной запуск: **Actions → Kernel build → Run workflow**.

Входы:

- `mode` — `verify` или `full`;
- `device` — кодовое имя;
- `runner` — `github-hosted` или `self-hosted`;
- `slot` — `1` / `0`;
- `clang_url` — тулчейн (по умолчанию AOSP clang 12).

### Про `full` на GitHub-hosted

Не заработает. Стандартный GitHub-hosted runner — это ~14 ГБ диска, а полная сборка ядра
нуждается примерно в 40 ГБ. Упаковка с `timeout-minutes: 350` на 4 ядрах тоже не успеет.

Варианты:

1. **`mode: verify` на `github-hosted`** — работает сразу, за ~15 минут, и отвечает на главный
   вопрос «собирается ли ReSukiSu с этим ядром».
2. **Self-hosted runner** — любая Linux-машина (в т.ч. VPS) с 60+ ГБ диска и 8+ ядрами.

### Настройка self-hosted runner

```bash
# на машине сборки (Linux x86_64)
mkdir -p ~/actions-runner && cd ~/actions-runner
# скачать runner нужной версии с https://github.com/actions/runner/releases
tar xvf actions-runner-linux-*.tar.gz

./config.sh --url https://github.com/timaa130704/android_kernel_samsung_exynos9820 \
             --token <RUNNER_TOKEN> --labels self-hosted --unattended
./run.sh
```

Настройки вкладки репозитория: **Settings → Actions → Runners → New self-hosted runner**.

Тулчейн можно положить на эту машину заранее и передать через переменную окружения:

```bash
CLANG_DIR=/home/user/Android/ToolChain/ZyClang-23 \
  ci/build-kernel.sh --device beyond1lte --mode full
```

### Артефакты и релизы

- `mode: full` складывает zip и `Image` в GitHub Actions Artifacts (срок хранения 30 дней).
- Дополнительно zip публикуется в rolling-релиз с тегом `ci-<device>` (prerelease) —
  ссылка стабильная, можно качать через `releases/download/ci-beyond1lte/...`.
- Логи ошибок компиляции всегда в выводе job'а; превью `.config` и версии ReSukiSu
  пишутся в summary.

## Что проверяет скрипт перед сборкой

Скрипт валит сборку с внятной ошибкой, если после `olddefconfig`:

- пропал `CONFIG_KSU_SUSFS=y` (значит choice откатился на tracepoint-хов, который на 4.14
  невозможен — без этой проверки падение случилось бы позже и с невнятным сообщением);
- не подтянут submodule с ReSukiSu (`drivers/kernelsu/Kbuild` отсутствует).

## Если сборка падает

1. Сначала прогнать `--mode verify` и приложить лог — обычно сразу видно, проблема в ReSukiSu
   или в ядре.
2. Если ReSukiSu не собирается — база `resukisu-qpr2` использует свежий `main` ReSukiSu
   (сильно переписанный). В исходном репозитории есть ветка `rksu-16` с уже проверенной
   связкой ReSukiSu + это ядро, но на старой версии ReSukiSu (плоская структура
   `allowlist.c` / `sucompat.c`). Она — готовый запасной вариант.
3. Если падает ядро, а не ReSukiSu — дело в тулчейне. Дерево рассчитано на clang 12
   (`build.config.universal9820`: `CLANG_VERSION=clang-4691093`). Слишком новый clang
   (14+) на дереве 4.14 обычно не собирается.