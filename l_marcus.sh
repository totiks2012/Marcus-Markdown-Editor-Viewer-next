#!/bin/bash
#set -x

# Исправте путь до своего каталога куда вы распаковали архив с дистрибутвом marcus

cd /home/live/.local/bin/marcus

# Проверка наличия xsel
if ! command -v xsel &> /dev/null; then
    echo "Ошибка: утилита xsel не установлена. Установите её с помощью 'sudo apt install xsel'."
    exit 1
fi


# Получение пути из буфера обмена
file_path=$(xsel -b | tr -d '\n')
if [[ -z "$file_path" ]]; then
    echo "Ошибка: буфер обмена пуст."
    exit 1
fi



# Проверка, что файл имеет расширение .md
if [[ ! "$file_path" =~ \.md$ ]]; then
    echo "Предупреждение: файл '$file_path' не имеет расширения .md, но продолжаем."
fi

# Запуск marcus.py с путем файла
wish ./marcus_w6.tcl "$file_path"

