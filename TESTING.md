# Тестирование Zipchik 0.2.2 / Zipchik 0.2.2 testing

## Русский

Релиз: [v0.2.2](https://github.com/alex1362/zipchik/releases/tag/v0.2.2) · только Apple Silicon · macOS 14+.

1. Скачайте DMG, перетащите «Зипчик» в Applications. При первом запуске preview-сборки macOS может попросить открыть приложение через Control-click → «Открыть».
2. Выделите обычный ZIP в Finder и нажмите пробел. Должны появиться «Содержимое архива», список и чекбоксы.
3. Отметьте один небольшой файл, нажмите «Извлечь выбранное…», выберите пустую папку и проверьте, что извлечён только этот файл.
4. Повторите пробел для `.7z`, `.rar` или `.tar.gz`, если такой архив есть.
5. Для парольного или многотомного архива выберите Finder → «Открыть с помощью → Зипчик». Должно открыться служебное окно; пароль не должен сохраняться после закрытия.

Просьба приложить к [Issues](https://github.com/alex1362/zipchik/issues) версию macOS, тип архива, ожидаемый и фактический результат. Не прикладывайте парольные файлы или пароли.

## English

Release: [v0.2.2](https://github.com/alex1362/zipchik/releases/tag/v0.2.2) · Apple Silicon only · macOS 14+.

1. Download the DMG and drag Zipchik to Applications. On first launch, macOS may require Control-click → **Open** because this preview is not notarized.
2. Select an ordinary ZIP in Finder and press Space. You should see archive contents, a file list, and checkboxes.
3. Select one small file, choose **Extract selected…**, select an empty folder, and verify that only that file was extracted.
4. Repeat with `.7z`, `.rar`, or `.tar.gz` if available.
5. For a password-protected or multi-volume archive, choose Finder → **Open With → Zipchik**. The helper window should open; the password must not persist after closing it.

Please report macOS version, archive type, expected result, and actual result in [Issues](https://github.com/alex1362/zipchik/issues). Do not attach password-protected archives or passwords.
