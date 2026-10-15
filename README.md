# ArticulationBox

Компактное меню артикуляций для MIDI-редактора REAPER. Интерфейс скрипта — на английском.

Один пакет включает основное поле, короткое меню у курсора и полное меню настроек. Поддерживаются keyswitch, переключение MIDI-каналов, индивидуальные банки треков, дефолтные артикуляции, сопровождение нот и защита высот keyswitch при транспонировании.

## Установка из одного файла

Скачайте `ArticulationBox_Install.lua`. В REAPER откройте **Actions > Show action list**, выберите **Main**, затем **New action > Load ReaScript**. Загрузите установщик и нажмите **Run/close**.

Установщик разместит нужные файлы, зарегистрирует экшны и запустит основную версию при наличии необходимого расширения. Файлы прежней установки, которые заменяются, копируются в резервную папку. Существующие личные банки и настройки сохраняются.

## Установка через ReaPack

Адрес репозитория для импорта:

```text
https://raw.githubusercontent.com/andreynovikov86-cmd/ArticulationBox/main/index.xml
```

В REAPER: **Extensions > ReaPack > Import repositories** → вставьте адрес → **Browse packages** → найдите **ArticulationBox** → **Install** → **Apply**.

Требуется расширение [js_ReaScriptAPI](https://github.com/juliansader/ReaExtensions). Установите его отдельно через ReaPack. После установки расширения перезапустите REAPER.

## Первый запуск

Откройте MIDI-айтем. В **Actions > MIDI Editor** запустите `Articulation_Manager.lua`. Клавишу быстрого выбора назначьте на `Articulation_Quick_Menu.lua` в том же разделе. Для сопровождения переключателей основной скрипт должен оставаться запущенным.

Банки создаются через **Settings > Banks > New**, артикуляции — через **Add articulation**. Автозапуск: **Settings > Run script on startup**. Сохраняйте проект, чтобы восстановить выбранные банки треков и назначения нот.

Личные банки, проекты и резервные копии пользователя в репозиторий не включены. Используйте один способ установки; при переходе на ReaPack перепривяжите горячие клавиши к экшнам новой установки.

Подробности: [инструкция](ArticulationBox/INSTALL_RU.txt). Сведения о стороннем коде: [THIRD_PARTY_NOTICES](ArticulationBox/THIRD_PARTY_NOTICES.txt).

## Выпуск обновления

Измените код пакета и увеличьте `@version` в `ArticulationBox/Articulation_Manager.lua`. Обновите `@changelog` и отправьте изменения в ветку `main`. Workflow использует [официальный индексатор ReaPack](https://github.com/cfillion/reapack-index); старые версии остаются в индексе, а ссылки указывают на зафиксированные коммиты.
