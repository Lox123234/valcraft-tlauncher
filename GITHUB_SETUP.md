# Публикация на GitHub

Предлагаемое имя: **`valcraft-tlauncher-setup`**

**About / Description:**

> Run Minecraft inside Valheim. Windows installer, TLauncher integration, Fabric support, setup guide and recovery tools.

**Topics:** `valcraft`, `valheim`, `minecraft`, `tlauncher`, `fabric`, `bepinex`, `reshade`, `powershell`, `windows`, `modding`

## Создание репозитория

1. Создайте **пустой** репозиторий `valcraft-tlauncher-setup` на GitHub. **Не создавайте автоматически README и LICENSE**, они уже есть.
2. Распакуйте подготовленный архив. Откройте терминал в корне проекта.
3. Введите следующие команды, заменив `YOUR_USERNAME` на логин GitHub:

```bash
git init
git add .
git commit -m "Initial release: ValCraft TLauncher setup"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/valcraft-tlauncher-setup.git
git push -u origin main
```

4. Откройте **Settings → General → Features**, включите Issues при необходимости.
5. В поле About вставьте Description выше и добавьте Topics.
6. Вкладка **Releases → Draft a new release**: тег `v0.1.0-tlauncher`, заголовок `ValCraft TLauncher Setup v0.1.0`. Архив установки можно прикрепить к релизу.

## Перед публикацией

- Проверьте `git status` и `git ls-files`.
- Убедитесь, что **нет** `runtime/`, `backup-before-valcraft/`, `installed-tlauncher.json`, `valcraft.local.json`, игровых миров, приватных конфигов и логов.
- Не называйте репозиторий «официальным ValCraft» — это отдельная адаптация.
- Сохраняйте оригинальные уведомления MIT и ссылку на исходный проект.
- Не включайте файлы игр, загруженные инсталляторы и пользовательский Minecraft-контент.
