#!/usr/bin/env tclsh

#
# A simple Markdown viewer written in Tcl/Tk, v0.1
# Модифицирован для поддержки открытия файлов из аргументов командной строки, 
# применения тёмной или светлой темы к интерфейсу и содержимому Markdown,
# а также добавления пункта меню "Экспорт в HTML", который сохраняет 
# HTML-результат в файл с именем исходного Markdown с применением параметров шрифта.
#

package require Tcl 8.6-
package require Tk
package require Tkhtml 3.0
package require Img
package require http
package require tls

#----------------------------------------------------------------------
# Чтение конфигурационного файла (marcus.conf)
#----------------------------------------------------------------------

# Значения настроек по умолчанию
set config(theme) "light"
set config(font_family) "Helvetica"
set config(font_size) 12

proc readConfig {filename} {
    if {![file exists $filename]} {
        return
    }
    set inDefaultSection 0
    set fp [open $filename r]
    while {[gets $fp line] >= 0} {
        set trimmed_line [string trim $line]
        if {$trimmed_line eq "" || [string index $trimmed_line 0] eq "#"} {
            continue
        }
        if {[regexp {^\[(.*)\]$} $trimmed_line -> section]} {
            if {[string tolower $section] eq "default"} {
                set inDefaultSection 1
            } else {
                set inDefaultSection 0
            }
            continue
        }
        if {$inDefaultSection} {
            if {[regexp {([^=]+)=(.+)} $trimmed_line -> key value]} {
                set key [string trim $key]
                set value [string trim $value]
                set ::config($key) $value
            }
        }
    }
    close $fp
}

readConfig "marcus.conf"

#----------------------------------------------------------------------
# Применение глобальной темы для остальных виджетов
#----------------------------------------------------------------------

switch -- [string tolower $::config(theme)] {
    "dark" {
        option add *background "#2e2e2e"
        option add *foreground "#ffffff"
        option add *activeBackground "#5e5e5e"
        option add *activeForeground "#ffffff"
        option add *highlightBackground "#5e5e5e"
        option add *highlightColor "#ffffff"
    }
    "light" {
        option add *background "#ffffff"
        option add *foreground "#000000"
        option add *activeBackground "#e5e5e5"
        option add *activeForeground "#000000"
        option add *highlightBackground "#e5e5e5"
        option add *highlightColor "#000000"
    }
}

font create mdFont -family $::config(font_family) -size $::config(font_size)
option add *Font mdFont

#----------------------------------------------------------------------
# Настройка окна и подключение пакетов для обработки Markdown
#----------------------------------------------------------------------

wm geometry . 960x660+20+10

set useCmark 1
if {$useCmark == 1} {
    if {[catch {package require cmark}]} {
        package require Markdown
        set useCmark 0
    }
} else {
    package require Markdown
}

http::register https 443 [list ::tls::socket -ssl3 0 -ssl2 0 -tls1 1]

#----------------------------------------------------------------------
# Формирование меню
#----------------------------------------------------------------------

ttk::frame .menubar -relief raised -borderwidth 2
pack .menubar -side top -fill x

ttk::menubutton .menubar.file -text File -menu .menubar.file.menu
menu .menubar.file.menu -tearoff 0
.menubar.file.menu add command -label Open  -command Open
.menubar.file.menu add command -label "Экспорт в HTML" -command ExportHtml
.menubar.file.menu add command -label Close -command Close
.menubar.file.menu add command -label Quit  -command Exit

ttk::menubutton .menubar.help -text Help -menu .menubar.help.menu
menu .menubar.help.menu -tearoff 0
.menubar.help.menu add command -label About -command HelpAbout
pack .menubar.file .menubar.help -side left

menu .menu
foreach i [list Exit] {
    .menu add command -label $i -command $i
}
if {[tk windowingsystem]=="aqua"} {
    bind . <2> "tk_popup .menu %X %Y"
    bind . <Control-1> "tk_popup .menu %X %Y"
} else {
    bind . <3> "tk_popup .menu %X %Y"
}

#----------------------------------------------------------------------
# Создание виджета HTML с прокруткой
#----------------------------------------------------------------------

pack [ttk::scrollbar .vsb -orient vertical -command {.label yview}] -side right -fill y
html .label -yscrollcommand {.vsb set} -shrink 1 -imagecmd GetImageCmd
.label handler "node" "a" ATagHandler
pack .label -fill both -expand 1

bind all <F1> HelpAbout
bind .label <Prior> { %W yview scroll -1 pages }
bind .label <Next>  { %W yview scroll 1 pages }
bind .label <Up>    { %W yview scroll -1 pages }
bind .label <Down>  { %W yview scroll 1 pages }
bind .label <Left>  { %W yview scroll -1 pages }
bind .label <Right> { %W yview scroll 1 pages }
bind .label <Home>  { %W yview moveto 0 }
bind .label <End>   { %W yview moveto 1 }
bind .label <1> { HrefBinding .label %x %y }

#----------------------------------------------------------------------
# Вспомогательные процедуры
#----------------------------------------------------------------------

proc DownloadData {uri} {
    set token [::http::geturl $uri]
    set data [::http::data $token]
    set ncode [::http::ncode $token]
    ::http::cleanup $token
    if {$ncode != 200} {
        return -code error "ERROR"
    }
    return $data
}

proc invokeBrowser {url} {
    set commands {xdg-open open start}
    foreach browser $commands {
        if {$browser eq "start"} {
            set command [list {*}[auto_execok start] {}]
        } else {
            set command [auto_execok $browser]
        }
        if {[string length $command]} {
            break
        }
    }
    if {[string length $command] == 0} {
        return -code error "couldn't find browser"
    }
    if {[catch {exec {*}$command $url &} error]} {
        return -code error "couldn't execute '$command': $error"
    }
}

proc HrefBinding {hwidget x y} {
    set node_data [$hwidget node -index $x $y]
    if {[llength $node_data] >= 2} {
        set node [lindex $node_data 0]
    } else {
        set node $node_data
    }
    if {[catch {set node [$node parent]}] == 0} {
        if {[$node tag] eq "a"} {
            set uri [string trim [$node attr -default "" href]]
            if {$uri ne "" && $uri ne "#"} {
                if {[string equal -length 8 $uri "https://"] || [string equal -length 7 $uri "http://"]} {
                    catch {invokeBrowser $uri}
                }
            }
        }
    }
}

proc GetImageCmd {uri} {
    if {[file exists $uri] && ![file isdirectory $uri]} {
        image create photo $uri -file $uri
        return $uri
    }
    set fname [file join $::basedir $uri]
    if {[file exists $fname] && ![file isdirectory $fname]} {
        image create photo $uri -file $fname
        return $uri
    }
    if {[string equal -length 8 $uri "https://"] || [string equal -length 7 $uri "http://"]} {
        if {[catch {set data [DownloadData $uri]}] == 1} {
            return ""
        }
        if {[catch {image create photo $uri -data $data}] == 1} {
            return ""
        }
        return $uri
    }
    return ""
}

proc ATagHandler {node} {
    if {[$node tag] eq "a"} {
        set href [string trim [$node attr -default "" href]]
        if {[string first "#" $href] == -1 && [string trim [lindex [$node attr] 0]] ne "name"} {
            $node dynamic set link
        }
    }
}

#----------------------------------------------------------------------
# Открытие Markdown-файла и обработка HTML
#----------------------------------------------------------------------

# Глобальные переменные для хранения имени исходного файла и текущего HTML
set ::currentMdFile ""
set ::currentHtml ""

proc OpenMdFile {filename} {
    set infile [open $filename]
    set md [read $infile]
    close $infile
    if {$::useCmark == 1} {
        set data [cmark::render -to html $md]
    } else {
        set data [::Markdown::convert $md]
    }
    set ::currentHtml $data
    set ::currentMdFile $filename
    return $data
}

# Обновлённая процедура ResetAndParse:
# Если в HTML есть тег <body>, то в него добавляются атрибуты style, 
# задающие фон, цвет текста и параметры шрифта (семейство и размер) из настроек.
proc ResetAndParse {data} {
    set fontFamily $::config(font_family)
    set fontSize $::config(font_size)
    if {[string tolower $::config(theme)] eq "dark"} {
        if {[regexp {<body([^>]*)>} $data]} {
            regsub -all {<body([^>]*)>} $data "<body\\1 style=\"background-color: #2e2e2e; color: #ffffff; font-family: $fontFamily; font-size: ${fontSize}px;\">" data
        } else {
            set data "<body style=\"background-color: #2e2e2e; color: #ffffff; font-family: $fontFamily; font-size: ${fontSize}px;\">$data</body>"
        }
    } elseif {[string tolower $::config(theme)] eq "light"} {
        if {[regexp {<body([^>]*)>} $data]} {
            regsub -all {<body([^>]*)>} $data "<body\\1 style=\"background-color: #ffffff; color: #000000; font-family: $fontFamily; font-size: ${fontSize}px;\">" data
        } else {
            set data "<body style=\"background-color: #ffffff; color: #000000; font-family: $fontFamily; font-size: ${fontSize}px;\">$data</body>"
        }
    }
    set ::currentHtml $data
    .label reset
    .label parse -final $data
    focus .label
}

proc Open {} {
    set types {{{Markdown Files} {.md}}}
    set openfile [tk_getOpenFile -filetypes $types -defaultextension md]
    if {$openfile ne ""} {
        set ::basedir [file dirname $openfile]
        set data [OpenMdFile $openfile]
        ResetAndParse $data
    }
}

proc Close {} {
    .label reset
}

proc Exit {} {
    set answer [tk_messageBox -message "Really quit?" -type yesno -icon warning]
    if {$answer eq "yes"} { exit }
}

proc HelpAbout {} {
    tk_messageBox -title "About" -type ok -message "A simple markdown file viewer."
}

#----------------------------------------------------------------------
# Экспорт HTML в файл
#----------------------------------------------------------------------

proc ExportHtml {} {
    if {$::currentHtml eq "" || $::currentMdFile eq ""} {
        tk_messageBox -message "Нет данных для экспорта." -type ok -icon info
        return
    }
    set mdName [file tail $::currentMdFile]
    set baseName [file rootname $mdName]
    set htmlFile "${baseName}.html"
    set outPath [file join [file dirname $::currentMdFile] $htmlFile]
    set fp [open $outPath w]
    puts $fp $::currentHtml
    close $fp
    tk_messageBox -message "Экспорт завершён: $outPath" -type ok -icon info
}

#----------------------------------------------------------------------
# Главный вход: Обработка аргументов командной строки
#----------------------------------------------------------------------

if {$argc > 0} {
    foreach file $argv {
        if {[file exists $file]} {
            set ::basedir [file dirname $file]
            set data [OpenMdFile $file]
            ResetAndParse $data
        } else {
            puts "File $file does not exist."
        }
    }
} else {
    Open
}

tkwait window .