#!/usr/bin/wish
package require Tk

# Устанавливаем системную кодировку UTF-8
encoding system utf-8

# Проверяем локаль
if {[info exists ::env(LANG)] && ![string match -nocase "*utf-8*" $::env(LANG)]} {
    puts "Warning: System locale is '$::env(LANG)', expected UTF-8 (e.g., ru_RU.UTF-8)"
}

# Создаем главное окно
wm title . "Markdown Editor"
wm attributes . -zoomed 1 ;# Разворачиваем окно на весь экран

# Глобальные переменные для настроек
set fontSize 12
set theme "light"
set configFile [file join [pwd] temarcus.conf]
set buttonSize 14 ;# Размер шрифта для кнопок
array set listNumbers {} ;# Хранит нумерацию для каждого уровня вложенности
set search_query "" ;# Переменная для хранения поискового запроса
set search_pos "" ;# Переменная для хранения текущей позиции поиска
set fileModified 0 ;# Флаг для отслеживания изменений в файле
set currentFile "" ;# Текущий открытый файл

# Процедура для создания границ undo-операций с проверкой
proc markUndoBoundary {} {
    # Проверка, не пустой ли текст
    if {[string length [.editor get 1.0 end-1c]] > 0} {
        catch {.editor edit separator}
    }
}

# Процедура безопасного выполнения undo
proc safeUndo {} {
    if {[.editor edit canundo]} {
        .editor edit undo
    }
}

# Процедура безопасного выполнения redo
proc safeRedo {} {
    if {[.editor edit canredo]} {
        .editor edit redo
    }
}

# Загрузка настроек из файла
proc loadConfig {} {
    global fontSize theme configFile buttonSize
    if {[file exists $configFile]} {
        if {[catch {
            set fp [open $configFile r]
            fconfigure $fp -encoding utf-8
            set data [read $fp]
            close $fp
            foreach line [split $data \n] {
                if {[regexp {^fontSize=(\d+)$} $line -> size]} {
                    set fontSize $size
                } elseif {[regexp {^theme=(light|dark)$} $line -> th]} {
                    set theme $th
                } elseif {[regexp {^buttonSize=(\d+)$} $line -> bsize]} {
                    set buttonSize $bsize
                }
            }
        } err]} {
            puts "Error loading config: $err"
        }
    }
}

# Сохранение настроек в файл
proc saveConfig {} {
    global fontSize theme configFile buttonSize
    if {[catch {
        set fp [open $configFile w]
        fconfigure $fp -encoding utf-8
        puts $fp "fontSize=$fontSize"
        puts $fp "theme=$theme"
        puts $fp "buttonSize=$buttonSize"
        close $fp
    } err]} {
        tk_messageBox -message "Ошибка при сохранении настроек: $err" -type ok -icon error
    }
}

# Загружаем настройки при запуске
loadConfig

# Создаем фрейм для панели инструментов
frame .toolbar -relief raised -bd 1
pack .toolbar -side top -fill x

# Функция для создания кнопки с заданным размером шрифта и всплывающей подсказкой
proc createButton {path text command tooltip {width 0}} {
    global buttonSize
    button $path -text $text -command $command -font "Arial $buttonSize" -height 2 -width $width
    bind $path <Enter> [list showTooltip %W $tooltip]
    bind $path <Leave> [list hideTooltip]
    return $path
}

# Реализация всплывающих подсказок
proc showTooltip {widget text} {
    global tooltipWin
    if {[info exists tooltipWin] && [winfo exists $tooltipWin]} {
        destroy $tooltipWin
    }
    set tooltipWin [toplevel .tooltip -background lightyellow -borderwidth 1 -relief solid]
    wm overrideredirect $tooltipWin 1
    label $tooltipWin.label -text $text -background lightyellow -font "Arial 10"
    pack $tooltipWin.label
    set x [expr {[winfo rootx $widget] + [winfo width $widget]/2}]
    set y [expr {[winfo rooty $widget] + [winfo height $widget] + 5}]
    wm geometry $tooltipWin +$x+$y
}

proc hideTooltip {} {
    global tooltipWin
    if {[info exists tooltipWin] && [winfo exists $tooltipWin]} {
        destroy $tooltipWin
    }
}

# Кнопки для форматирования Markdown и управления файлами
createButton .toolbar.new "📄 New" newFile "Создать новый документ"
createButton .toolbar.open "📂 Open" openFile "Открыть Markdown-файл"
createButton .toolbar.save "💾 Save" {saveCurrentFile 0} "Сохранить текущий файл"
createButton .toolbar.saveas "💾 Save As" {saveCurrentFile 1} "Сохранить Markdown-файл как..."
createButton .toolbar.undo "↩️ Отмена" {safeUndo} "Отменить последнее действие"
createButton .toolbar.redo "↪️ Повтор" {safeRedo} "Повторить отменённое действие"
createButton .toolbar.bold "** **" {insertMarkdown "**" "**"} "Выделить текст жирным"
createButton .toolbar.italic "* *" {insertMarkdown "*" "*"} "Выделить текст курсивом"
createButton .toolbar.underline "U_" {insertMarkdown "**<u>" "</u>**"} "Подчеркнуть текст"
createButton .toolbar.header "##" {insertMarkdown "## " ""} "Добавить заголовок"
createButton .toolbar.list "1." {insertOrderedList} "Добавить упорядоченный список"
createButton .toolbar.link "[]()" {insertMarkdown "\[" "\]()"} "Вставить ссылку"
createButton .toolbar.image "🖼️" insertImage "Вставить изображение"
createButton .toolbar.code "```" {insertMarkdown "```\n" "\n```"} "Вставить блок кода"
createButton .toolbar.quote ">" {insertMarkdown "> " ""} "Добавить цитату"
createButton .toolbar.preview "👁️ Preview" previewMarkdown "Предпросмотр Markdown"

# Кнопки для изменения размера кнопок
createButton .toolbar.btnPlus "➕" {changeButtonSize 2} "Увеличить размер кнопок" 3
createButton .toolbar.btnMinus "➖" {changeButtonSize -2} "Уменьшить размер кнопок" 3

# Чекбокс для переключения темы
checkbutton .toolbar.theme -text "Dark Theme" -variable themeToggle -command toggleTheme -font "Arial $buttonSize"
bind .toolbar.theme <Enter> {showTooltip .toolbar.theme "Переключить тёмную/светлую тему"}
bind .toolbar.theme <Leave> {hideTooltip}
if {$theme == "dark"} {
    set themeToggle 1
} else {
    set themeToggle 0
}

# Размещаем кнопки
pack .toolbar.new .toolbar.open .toolbar.save .toolbar.saveas -side left -padx 2 -pady 2
pack .toolbar.undo .toolbar.redo -side left -padx 2 -pady 2
pack .toolbar.bold .toolbar.italic .toolbar.underline .toolbar.header .toolbar.list .toolbar.link .toolbar.image .toolbar.code .toolbar.quote .toolbar.preview -side left -padx 2 -pady 2
pack .toolbar.btnPlus .toolbar.btnMinus -side left -padx 2 -pady 2
pack .toolbar.theme -side left -padx 2 -pady 2

# Создаем фрейм для поиска
frame .search_frame
pack .search_frame -side bottom -fill x -padx 5 -pady 5

# Поле ввода для поиска
entry .search_frame.search_entry -font "Arial $fontSize"
pack .search_frame.search_entry -side left -padx 5
.search_frame.search_entry insert 0 "Поиск..."

# Кнопки для навигации по результатам поиска
createButton .search_frame.prev "◄" search_prev "Предыдущее совпадение поиска" 3
createButton .search_frame.next "►" search_next "Следующее совпадение поиска" 3
pack .search_frame.prev .search_frame.next -side left -padx 5

# Создаем текстовую область с включенной функцией отмены
text .editor -wrap word -undo true -autoseparators true -maxundo 2000 -font "Arial $fontSize" -yscrollcommand ".scroll set"
scrollbar .scroll -command ".editor yview"
pack .scroll -side right -fill y
pack .editor -side top -fill both -expand true -padx 5 -pady 5

# Применение темы
proc applyTheme {} {
    global theme
    if {$theme == "dark"} {
        .editor configure -background "#2e2e2e" -foreground "#ffffff" -insertbackground "#ffffff"
        .toolbar configure -background "#3c3c3c"
        .search_frame configure -background "#3c3c3c"
        . configure -background "#3c3c3c"
        .search_frame.search_entry configure -background "#3c3c3c" -foreground "#ffffff" -insertbackground "#ffffff"
        foreach w [winfo children .toolbar] {
            if {[winfo class $w] == "Button" || [winfo class $w] == "Checkbutton"} {
                $w configure -background "#3c3c3c" -foreground "#ffffff" -activebackground "#555555"
            }
        }
        foreach w [winfo children .search_frame] {
            if {[winfo class $w] == "Button"} {
                $w configure -background "#3c3c3c" -foreground "#ffffff" -activebackground "#555555"
            }
        }
        .scroll configure -background "#3c3c3c" -troughcolor "#2e2e2e"
    } else {
        .editor configure -background "white" -foreground "black" -insertbackground "black"
        .toolbar configure -background "#d9d9d9"
        .search_frame configure -background "#d9d9d9"
        . configure -background "#d9d9d9"
        .search_frame.search_entry configure -background "white" -foreground "black" -insertbackground "black"
        foreach w [winfo children .toolbar] {
            if {[winfo class $w] == "Button" || [winfo class $w] == "Checkbutton"} {
                $w configure -background "#d9d9d9" -foreground "black" -activebackground "#e0e0e0"
            }
        }
        foreach w [winfo children .search_frame] {
            if {[winfo class $w] == "Button"} {
                $w configure -background "#d9d9d9" -foreground "black" -activebackground "#e0e0e0"
            }
        }
        .scroll configure -background "#d9d9d9" -troughcolor "#f0f0f0"
    }
}

# Переключение темы
proc toggleTheme {} {
    global theme themeToggle
    if {$themeToggle} {
        set theme "dark"
    } else {
        set theme "light"
    }
    applyTheme
    saveConfig
}

# Применяем тему при запуске
applyTheme

# Нормализация переводов строк
proc normalizeLineEndings {text} {
    return [string map {"\r\n" "\n" "\r" "\n"} $text]
}

# Процедура для поиска текста
proc search_text {} {
    global search_query search_pos
    set search_query [.search_frame.search_entry get]
    if {$search_query eq "" || $search_query eq "Поиск..."} {
        return
    }
    .editor tag remove sel 1.0 end
    set start_pos [expr {$search_pos eq "" ? "1.0" : $search_pos}]
    set search_pos [.editor search -nocase -forward $search_query $start_pos end]
    if {$search_pos ne ""} {
        set end_pos [.editor index "$search_pos + [string length $search_query] chars"]
        .editor tag add sel $search_pos $end_pos
        .editor see $search_pos
    } else {
        tk_messageBox -message "Текст '$search_query' не найден" -type ok -icon info
        set search_pos ""
    }
}

# Процедура для поиска предыдущего совпадения
proc search_prev {} {
    global search_query search_pos
    if {$search_query eq "" || $search_query eq "Поиск..."} {
        return
    }
    if {$search_pos eq ""} {
        set search_pos "end"
    }
    .editor tag remove sel 1.0 end
    set new_pos [.editor search -nocase -backward $search_query $search_pos 1.0]
    if {$new_pos ne ""} {
        set search_pos $new_pos
        set end_pos [.editor index "$search_pos + [string length $search_query] chars"]
        .editor tag add sel $search_pos $end_pos
        .editor see $search_pos
    } else {
        tk_messageBox -message "Предыдущее совпадение не найдено" -type ok -icon info
        set search_pos ""
    }
}

# Процедура для поиска следующего совпадения
proc search_next {} {
    global search_query search_pos
    if {$search_query eq "" || $search_query eq "Поиск..."} {
        return
    }
    if {$search_pos eq ""} {
        set search_pos "1.0"
    } else {
        set search_pos [.editor index "$search_pos + [string length $search_query] chars"]
    }
    .editor tag remove sel 1.0 end
    set new_pos [.editor search -nocase -forward $search_query $search_pos end]
    if {$new_pos ne ""} {
        set search_pos $new_pos
        set end_pos [.editor index "$search_pos + [string length $search_query] chars"]
        .editor tag add sel $search_pos $end_pos
        .editor see $search_pos
    } else {
        tk_messageBox -message "Следующее совпадение не найдено" -type ok -icon info
        set search_pos ""
    }
}

# Привязка клавиши Enter для запуска поиска
bind .search_frame.search_entry <Return> {search_text}

# Очистка поля поиска при фокусе
bind .search_frame.search_entry <FocusIn> {
    if {[.search_frame.search_entry get] eq "Поиск..."} {
        .search_frame.search_entry delete 0 end
    }
}

# Восстановление placeholder при потере фокуса, если поле пустое
bind .search_frame.search_entry <FocusOut> {
    if {[.search_frame.search_entry get] eq ""} {
        .search_frame.search_entry insert 0 "Поиск..."
    }
}

# Процедура для изменения размера шрифта
proc changeFontSize {delta} {
    global fontSize
    set newSize [expr {$fontSize + $delta}]
    if {$newSize >= 8 && $newSize <= 72} {
        set fontSize $newSize
        .editor configure -font "Arial $fontSize"
        .search_frame.search_entry configure -font "Arial $fontSize"
        saveConfig
    }
}

# Процедура для изменения размера кнопок
proc changeButtonSize {delta} {
    global buttonSize
    set newSize [expr {$buttonSize + $delta}]
    if {$newSize >= 10 && $newSize <= 36} {
        set buttonSize $newSize
        updateButtonSizes
        saveConfig
    }
}

# Обновление размера всех кнопок
proc updateButtonSizes {} {
    global buttonSize
    foreach w [winfo children .toolbar] {
        if {[winfo class $w] == "Button" || [winfo class $w] == "Checkbutton"} {
            $w configure -font "Arial $buttonSize"
        }
    }
    foreach w [winfo children .search_frame] {
        if {[winfo class $w] == "Button"} {
            $w configure -font "Arial $buttonSize"
        }
    }
}

# Отслеживание изменений в тексте - улучшенная версия
proc trackChanges {} {
    global fileModified
    if {![.editor edit modified]} {
        return
    }
    markUndoBoundary
    set fileModified 1
    .editor edit modified 0
}

# Процедура для вставки Markdown-тегов
proc insertMarkdown {startTag endTag} {
    global fileModified
    markUndoBoundary
    set sel [.editor tag ranges sel]
    if {$sel != ""} {
        # Если есть выделение, обрамляем его тегами
        set start [lindex $sel 0]
        set end [lindex $sel 1]
        .editor insert $end $endTag
        .editor insert $start $startTag
    } else {
        # Если нет выделения, вставляем теги в позицию курсора
        .editor insert insert $startTag
        .editor insert insert $endTag
        .editor mark set insert "insert - [string length $endTag] chars"
    }
    markUndoBoundary
    set fileModified 1
}

# Процедура для вставки упорядоченного списка
proc insertOrderedList {} {
    global listNumbers fileModified
    markUndoBoundary
    set sel [.editor tag ranges sel]
    if {$sel != ""} {
        # Если есть выделение, вставляем начальный пункт
        set start [lindex $sel 0]
        .editor insert $start "1. "
        set listNumbers(0) 1
        markUndoBoundary
        set fileModified 1
        return
    }

    # Получаем текущую позицию курсора
    set cursorPos [.editor index insert]
    set currentLine [lindex [split $cursorPos .] 0]
    set currentCol [lindex [split $cursorPos .] 1]

    # Получаем текст текущей строки
    set currentLineText [.editor get "$currentLine.0" "$currentLine.0 lineend"]
    set indent ""
    set level 0
    set number 1

    # Определяем текущий уровень вложенности на основе отступов в текущей строке
    if {[regexp {^(\s*)} $currentLineText -> spaces]} {
        set spaceCount [string length $spaces]
        set level [expr {$spaceCount / 2}]
        set indent [string repeat "  " $level]
    }

    # Проверяем предыдущую строку для определения нумерации и уровня
    set prevLineNum [expr {$currentLine - 1}]
    if {$prevLineNum > 0} {
        set prevLineText [.editor get "$prevLineNum.0" "$prevLineNum.0 lineend"]
        if {$prevLineText eq "" && $level == 0} {
            # Сбрасываем нумерацию после пустой строки
            array unset listNumbers
            set number 1
        } elseif {[regexp {^(\s*)(\d+)\.\s} $prevLineText -> prevSpaces num]} {
            set prevSpaceCount [string length $prevSpaces]
            set prevLevel [expr {$prevSpaceCount / 2}]
            if {$level == $prevLevel} {
                # Тот же уровень вложенности, увеличиваем номер
                if {[info exists listNumbers($level)]} {
                    set number [expr {$listNumbers($level) + 1}]
                }
            } elseif {$level > $prevLevel} {
                # Новый, более глубокий уровень, начинаем с 1
                set number 1
            } elseif {$level < $prevLevel} {
                # Меньший уровень, используем нумерацию для этого уровня
                if {[info exists listNumbers($level)]} {
                    set number [expr {$listNumbers($level) + 1}]
                }
            }
        } else {
            # Если предыдущая строка не список, сбрасываем нумерацию
            set number 1
        }
    }

    # Проверяем, нужно ли добавлять новый пункт на следующей строке
    set insertNewLine 0
    if {[regexp {^\s*\d+\.\s*.+} $currentLineText] || ([regexp {^\s*\d+\.\s*$} $currentLineText] && $currentCol >= [string length $currentLineText])} {
        set insertNewLine 1
    }

    if {$insertNewLine} {
        # Добавляем новый пункт на следующей строке
        .editor insert "$currentLine.end" "\n$indent$number. "
        incr currentLine
    } else {
        # Если строка пустая или не требует новой строки, заменяем содержимое
        .editor delete "$currentLine.0" "$currentLine.0 lineend"
        .editor insert "$currentLine.0" "$indent$number. "
    }

    # Обновляем нумерацию для текущего уровня
    set listNumbers($level) $number

    # Устанавливаем курсор в конец вставленного текста
    set cursorPos "$currentLine.[expr {[string length $indent] + [string length "$number. "]}]"
    .editor mark set insert $cursorPos
    markUndoBoundary
    set fileModified 1
}

# Процедура для увеличения уровня вложенности
proc increaseIndent {} {
    global fileModified
    markUndoBoundary
    set cursorPos [.editor index insert]
    set currentLine [lindex [split $cursorPos .] 0]
    set lineText [.editor get "$currentLine.0" "$currentLine.0 lineend"]
    if {[regexp {^(\s*)(\d+\.\s.*)?$} $lineText -> spaces rest]} {
        set newIndent [string cat $spaces "  "]
        .editor delete "$currentLine.0" "$currentLine.0 lineend"
        .editor insert "$currentLine.0" "$newIndent$rest"
        .editor mark set insert "$currentLine.[expr {[string length $newIndent] + [string length $rest]}]"
    } else {
        .editor insert "$currentLine.0" "  "
        .editor mark set insert "insert + 2 chars"
    }
    markUndoBoundary
    set fileModified 1
}

# Процедура для уменьшения уровня вложенности
proc decreaseIndent {} {
    global fileModified
    markUndoBoundary
    set cursorPos [.editor index insert]
    set currentLine [lindex [split $cursorPos .] 0]
    set lineText [.editor get "$currentLine.0" "$currentLine.0 lineend"]
    if {[regexp {^(\s{2,})(\d+\.\s.*)?$} $lineText -> spaces rest]} {
        set newIndent [string range $spaces 2 end]
        .editor delete "$currentLine.0" "$currentLine.0 lineend"
        .editor insert "$currentLine.0" "$newIndent$rest"
        .editor mark set insert "$currentLine.[expr {[string length $newIndent] + [string length $rest]}]"
    }
    markUndoBoundary
    set fileModified 1
}

# Процедура для вставки изображения
proc insertImage {} {
    global fileModified
    set file [tk_getOpenFile -filetypes {{{Images} {.png .jpg .jpeg .gif}}} -title "Выбрать изображение"]
    if {$file != ""} {
        # Исправление экранирования путей
        set escapedFile $file
        # Преобразуем обратные слэши в прямые для Markdown
        regsub -all {\\} $escapedFile "/" escapedFile
        # Экранируем специальные символы
        set escapedFile [string map {" " "%20" "(" "%28" ")" "%29"} $escapedFile]
        set markdownImage "!\[Alt text\]($escapedFile)"
        
        markUndoBoundary
        .editor insert insert $markdownImage
        markUndoBoundary
        set fileModified 1
    }
}

# Процедура для создания нового документа
proc newFile {} {
    global fileModified currentFile
    if {$fileModified} {
        set answer [tk_messageBox -message "Сохранить изменения перед созданием нового файла?" -type yesnocancel -icon question]
        if {$answer == "yes"} {
            saveCurrentFile 0
            if {$fileModified} {
                # Если после попытки сохранения файл всё ещё помечен как изменённый, 
                # значит сохранение не выполнено успешно
                return
            }
        } elseif {$answer == "cancel"} {
            return
        }
    }
    .editor delete 1.0 end
    set fileModified 0
    set currentFile ""
    wm title . "Markdown Editor - New Document"
    .editor edit reset
    markUndoBoundary
}

# Процедура для открытия файла
proc openFile {} {
    global fileModified currentFile
    if {$fileModified} {
        set answer [tk_messageBox -message "Сохранить изменения перед открытием нового файла?" -type yesnocancel -icon question]
        if {$answer == "yes"} {
            saveCurrentFile 0
            if {$fileModified} {
                # Если после попытки сохранения файл всё ещё помечен как изменённый, 
                # значит сохранение не выполнено успешно
                return
            }
        } elseif {$answer == "cancel"} {
            return
        }
    }
    set file [tk_getOpenFile -filetypes {{{Markdown Files} {.md .markdown}} {{All Files} {*.*}}} -title "Открыть Markdown-файл"]
    if {$file != ""} {
        if {[catch {
            set fp [open $file r]
            fconfigure $fp -encoding utf-8 -translation auto
            set content [read $fp]
            close $fp
            
            # Нормализация символов перевода строки
            set content [normalizeLineEndings $content]
            
            .editor delete 1.0 end
            .editor insert 1.0 $content
            .editor edit reset
            markUndoBoundary
            set fileModified 0
            set currentFile $file
            wm title . "Markdown Editor - [file tail $file]"
        } err]} {
            tk_messageBox -message "Ошибка при открытии файла: $err" -type ok -icon error
        }
    }
}

# Процедура для сохранения текущего файла
proc saveCurrentFile {forcePrompt} {
    global fileModified currentFile
    
    # Если нет текущего файла или требуется диалог "Сохранить как"
    if {$currentFile == "" || $forcePrompt} {
        set file [tk_getSaveFile -filetypes {{{Markdown Files} {.md .markdown}} {{All Files} {*.*}}} -title "Сохранить Markdown-файл как" -defaultextension .md]
        if {$file == ""} {
            return ;# Пользователь отменил сохранение
        }
        set currentFile $file
    }
    
    if {[catch {
        set content [.editor get 1.0 "end-1c"]
        # Нормализация символов перевода строки
        set content [normalizeLineEndings $content]
        
        set fp [open $currentFile w]
        fconfigure $fp -encoding utf-8 -translation lf
        puts -nonewline $fp $content
        close $fp
        set fileModified 0
        wm title . "Markdown Editor - [file tail $currentFile]"
    } err]} {
        tk_messageBox -message "Ошибка при сохранении файла: $err" -type ok -icon error
    }
}

# Процедура для предпросмотра
proc previewMarkdown {} {
    global fileModified currentFile
    set marcusScript [file join [pwd] marcus_w6.tcl]
    set mdFile ""
    
    if {$currentFile != "" && [file exists $currentFile]} {
        # Если файл сохранен, используем его абсолютный путь
        set mdFile [file normalize $currentFile]
    } else {
        # Если файл новый, сохраняем во временный файл
        set tmpFile [file join [pwd] tmp.md]
        if {[catch {
            set content [.editor get 1.0 "end-1c"]
            # Нормализация символов перевода строки
            set content [normalizeLineEndings $content]
            
            set fp [open $tmpFile w]
            fconfigure $fp -encoding utf-8 -translation lf
            puts -nonewline $fp $content
            close $fp
            
            # Используем абсолютный путь к tmp.md
            set mdFile [file normalize $tmpFile]
        } err]} {
            tk_messageBox -message "Ошибка при создании временного файла: $err" -type ok -icon error
            return
        }
    }
    
    if {[catch {
        if {[file exists $marcusScript]} {
            if {[auto_execok python3] != ""} {
                puts "DEBUG: Запуск предпросмотра с файлом: $mdFile"
                exec wish $marcusScript $mdFile &
            } else {
                tk_messageBox -message "Ошибка открытия." -type ok -icon error
            }
        } else {
            tk_messageBox -message "Скрипт marcus_w4.tcl не найден в текущей директории" -type ok -icon error
        }
    } err]} {
        tk_messageBox -message "Ошибка во время предпросмотра: $err" -type ok -icon error
    }
}

# Обработка закрытия окна
proc onClose {} {
    global fileModified
    if {$fileModified} {
        set answer [tk_messageBox -message "Сохранить изменения перед закрытием?" -type yesnocancel -icon question]
        if {$answer == "yes"} {
            saveCurrentFile 0
            if {!$fileModified} {
                destroy .
            }
        } elseif {$answer == "no"} {
            destroy .
        }
    } else {
        destroy .
    }
}

# Привязки для горячих клавиш
bind .editor <Control-b> {insertMarkdown "**" "**"; break}
bind .editor <Control-i> {insertMarkdown "*" "*"; break}
bind .editor <Control-u> {insertMarkdown "**<u>" "</u>**"; break}
bind .editor <Control-n> {newFile; break}
bind .editor <Control-o> {openFile; break}
bind .editor <Control-s> {saveCurrentFile 0; break}
bind .editor <Control-Shift-s> {saveCurrentFile 1; break}
bind .editor <Control-z> {safeUndo; break}
bind .editor <Control-y> {safeRedo; break}
bind .editor <Control-Shift-z> {safeRedo; break}
bind .editor <Control-q> {insertMarkdown "> " ""; break}
bind .editor <Control-a> {.editor tag add sel 1.0 end-1c; break}
bind .editor <Tab> {increaseIndent; break}
bind .editor <Shift-Tab> {decreaseIndent; break}

# Привязки для отслеживания изменений
bind .editor <KeyPress> {+trackChanges}
bind .editor <BackSpace> {+trackChanges}
bind .editor <Delete> {+trackChanges}
bind .editor <Return> {+trackChanges}

# Обработка скроллера с Ctrl для изменения размера шрифта
bind . <Control-MouseWheel> {
    if {%D > 0} {
        changeFontSize 1
    } elseif {%D < 0} {
        changeFontSize -1
    }
}
bind . <Control-Button-4> {changeFontSize 1}
bind . <Control-Button-5> {changeFontSize -1}

# Перехват события закрытия окна
wm protocol . WM_DELETE_WINDOW onClose

# Устанавливаем начальные границы undo
markUndoBoundary

# Фокус на текстовом поле
focus .editor