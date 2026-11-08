@echo off
rem ==========================================================================
rem  PDF-OCR 2.0  -  portable builder  +  the program itself
rem --------------------------------------------------------------------------
rem  This single file is both the builder and the source of the program:
rem
rem    * the batch part prepares Python and Tesseract and bundles them
rem    * everything after the line  #===PY_START===  is the Python program,
rem      which is extracted and packed into one single PDF-OCR.exe
rem
rem  First run  : creates PDF-OCR.exe next to this file
rem  After that : a double click, or dropping PDFs onto this file, starts the
rem               app immediately. Use  --rebuild  to build again.
rem
rem  No administrator rights, no registry entries, no telemetry, nothing is
rem  uploaded. Tesseract and Python are taken from this PC when present.
rem  Options:  --rebuild   build again        --check   only test the setup
rem            --keep      keep build files
rem ==========================================================================
setlocal EnableExtensions
set "APPNAME=PDF OCR"
set "APPVER=2.0"
title %APPNAME% %APPVER%
rem  MODEL: fast = small and quick, best = a bit more accurate, 3x bigger
set "MODEL=fast"
rem  WITHDND: 1 = try drag and drop support inside the window
set "WITHDND=1"
rem  COMPACT: 1 = pack the OCR engine into the exe compressed (about 3x
rem  smaller file, the engine is unpacked once on the first start)
set "COMPACT=1"
rem  languages that get baked into the exe. Trim the list to shrink it.
set "LANGS=eng hin mar guj ben pan tam tel kan mal urd ara fas rus ukr chi_sim chi_tra jpn kor spa fra deu por ita tur"
set "PYFOUND="
set "TESSDIR="
set "BUNDLE="
set "REBUILD="
set "CHECKONLY="
set "KEEP="
set "DROPPED="
set "RAWARGS="
title %APPNAME% %APPVER%
cd /d "%~dp0"

:pargs
if "%~1"=="" goto :pargsdone
if /i "%~1"=="--rebuild" set "REBUILD=1"
if /i "%~1"=="-r" set "REBUILD=1"
if /i "%~1"=="--check" set "CHECKONLY=1"
if /i "%~1"=="--keep" set "KEEP=1"
set "DROPCHECK=%~1"
if not "%DROPCHECK:~0,1%"=="-" set "DROPPED=%DROPPED% "%~1""
if not "%DROPCHECK:~0,1%"=="-" set "RAWARGS=%RAWARGS% "%~1""
shift
goto :pargs
:pargsdone

rem ------------------------------------------------- easy instant start path
if not defined REBUILD if exist "%~dp0PDF-OCR.exe" goto :launch

echo ==========================================================================
echo   %APPNAME% %APPVER%   portable builder
echo --------------------------------------------------------------------------
echo   This is a one time setup, it needs no administrator rights.
echo   English is ready offline, the other OCR models are downloaded once
echo   - about 30 MB in total - and are then part of PDF-OCR.exe forever.
echo ==========================================================================
echo   started %DATE% %TIME%
echo.

set "W=%~dp0_build"
if exist "%W%" rmdir /s /q "%W%" >nul 2>&1
mkdir "%W%" >nul 2>&1
if not exist "%W%" goto :err_work
mkdir "%W%\tesseract\tessdata\configs" >nul 2>&1

rem which downloader is available
set "CURL="
if exist "%SystemRoot%\System32\curl.exe" set "CURL=%SystemRoot%\System32\curl.exe"
if not defined CURL for %%C in (curl.exe) do if not "%%~$PATH:C"=="" set "CURL=%%~$PATH:C"

echo [1/7] Looking for Python ...
call :findpython
if not defined PYFOUND (
  echo       not found, downloading the official Python installer once
  set "PYSETUP=%W%\python-setup.exe"
  call :fetch "https://www.python.org/ftp/python/3.12.16/python-3.12.16-amd64.exe" "%PYSETUP%"
  call :big "%PYSETUP%" 20000000
  if errorlevel 1 goto :err_pydl
  echo       installing Python for this user only, no admin needed
  start /wait "" "%PYSETUP%" /quiet InstallAllUsers=0 PrependPath=0 Include_launcher=0 Include_test=0 Include_doc=0 Include_pip=1 Include_tcltk=1 TargetDir="%LOCALAPPDATA%\Programs\Python\Python312"
  call :findpython
)
if not defined PYFOUND goto :err_nopython
echo       using "%PYFOUND%"

echo [2/7] Checking the build tools ...
"%PYFOUND%" -m pip --version >nul 2>&1
if errorlevel 1 "%PYFOUND%" -m ensurepip --default-pip >nul 2>&1
"%PYFOUND%" -c "import pymupdf, PyInstaller" >nul 2>&1
if errorlevel 1 (
  echo       installing PyMuPDF and PyInstaller once for this user
  "%PYFOUND%" -m pip install --user --disable-pip-version-check --quiet --upgrade pip
  "%PYFOUND%" -m pip install --user --disable-pip-version-check --quiet pymupdf pyinstaller
)
"%PYFOUND%" -c "import pymupdf, PyInstaller" >nul 2>&1
if errorlevel 1 goto :err_pip
if "%WITHDND%"=="1" (
  "%PYFOUND%" -c "import tkinterdnd2" >nul 2>&1
  if errorlevel 1 (
    "%PYFOUND%" -m pip install --user --disable-pip-version-check --quiet tkinterdnd2
  )
  "%PYFOUND%" -c "import tkinterdnd2" >nul 2>&1
  if errorlevel 1 set "WITHDND=0"
)
echo       build tools ready

echo [3/7] Looking for the OCR engine Tesseract ...
call :findtess
if not defined TESSDIR (
  echo       not found, unpacking a portable copy instead of installing
  call :portabletess
)
if not defined TESSDIR goto :err_notess
echo       using "%TESSDIR%"

echo [4/7] Writing the program ...
set "SKIP="
for /f "tokens=1 delims=:" %%N in ('findstr /n /b /c:"#===PY_START===" "%~f0"') do if not defined SKIP set "SKIP=%%N"
if not defined SKIP goto :err_write
rem  "more +N" starts at line N+1, which is the first line of the program
more +%SKIP% "%~f0" > "%W%\pdfocr.py"
if not exist "%W%\pdfocr.py" goto :err_write
call :checkpy "%W%\pdfocr.py"
if errorlevel 1 goto :err_write

echo [5/7] Collecting the engine files for the exe ...
"%PYFOUND%" "%W%\pdfocr.py" --collect-engine "%TESSDIR%" "%W%\tesseract" > "%W%\collect.log" 2>&1
set "DLLCOUNT=0"
for %%F in ("%W%\tesseract\*.dll") do set /a DLLCOUNT+=1
if not exist "%W%\tesseract\tesseract.exe" goto :collect_manual
if %DLLCOUNT% LSS 3 goto :collect_manual
if not exist "%W%\tesseract\tessdata\configs\pdf" goto :collect_manual
if exist "%W%\collect.log" type "%W%\collect.log"
echo       engine copied with %DLLCOUNT% libraries, only what is needed
goto :models_now

:collect_manual
echo       doing it the safe way, copying the whole engine folder
copy /y "%TESSDIR%\tesseract.exe" "%W%\tesseract\" >nul 2>&1
copy /y "%TESSDIR%\*.dll" "%W%\tesseract\" >nul 2>&1
if exist "%TESSDIR%\tessdata\configs" xcopy /y /q /i "%TESSDIR%\tessdata\configs" "%W%\tesseract\tessdata\configs" >nul 2>&1
if exist "%TESSDIR%\tessdata\pdf.ttf" copy /y "%TESSDIR%\tessdata\pdf.ttf" "%W%\tesseract\tessdata\" >nul 2>&1
if not exist "%W%\tesseract\tesseract.exe" goto :err_engine
if not exist "%W%\tesseract\tessdata\configs\pdf" goto :err_engine
echo       whole engine copied

:models_now
echo [6/7] Preparing the language models ...
set "MODELCOUNT=0"
if /i "%MODEL%"=="best" (set "REPO=tessdata_best") else (set "REPO=tessdata_fast")
for %%L in (%LANGS%) do call :getmodel %%L
if defined MODELFAIL goto :err_lang
echo       %MODELCOUNT% model(s) added, all languages ready
if defined CHECKONLY goto :check_ok

:build_now
echo [7/7] Building PDF-OCR.exe ... this is the slow part, please wait
cd /d "%W%"
set "DND="
if "%WITHDND%"=="1" set "DND=--collect-all tkinterdnd2"
set "ENGINEDATA=tesseract;tesseract"
if "%COMPACT%"=="1" (
  echo       packing the OCR engine, this keeps the exe about 3x smaller
  "%PYFOUND%" "%W%\pdfocr.py" --pack-engine "%W%\tesseract" "%W%\tesseract.tar.xz" > "%W%\pack.log" 2>&1
  if not exist "%W%\tesseract.tar.xz" goto :err_build
  if exist "%W%\pack.log" type "%W%\pack.log"
  set "ENGINEDATA=tesseract.tar.xz;."
)
"%PYFOUND%" -m PyInstaller --noconfirm --clean --onefile --noconsole --noupx --name PDF-OCR --add-data "%ENGINEDATA%" --exclude-module tkinter.test --exclude-module unittest --exclude-module doctest --exclude-module pydoc --exclude-module pdb --exclude-module lib2to3 --exclude-module setuptools --exclude-module pkg_resources --exclude-module distutils %DND% pdfocr.py > build.log 2>&1
cd /d "%~dp0"
if not exist "%W%\dist\PDF-OCR.exe" goto :err_build
for %%A in ("%W%\dist\PDF-OCR.exe") do set "EXSIZE=%%~zA"
set /a EXMB=%EXSIZE%/1048576

echo       checking the finished program ...
"%W%\dist\PDF-OCR.exe" --selftest
set "REPORT=%W%\dist\PDF-OCR-selftest.txt"
if not exist "%REPORT%" set "REPORT=%TEMP%\PDF-OCR-selftest.txt"
findstr /c:"result  : PASS" "%REPORT%" >nul 2>&1
if errorlevel 1 goto :warn_selftest

copy /y "%W%\dist\PDF-OCR.exe" "%~dp0PDF-OCR.exe" >nul 2>&1
if not exist "%~dp0PDF-OCR.exe" goto :err_copy
if defined KEEP goto :keep_build
rmdir /s /q "%W%" >nul 2>&1

echo.
echo ==========================================================================
echo   DONE.  PDF-OCR.exe  -  %EXMB% MB  -  is ready in this folder:
echo   %~dp0
echo --------------------------------------------------------------------------
echo   From now on a double click starts the program at once, and PDF files
echo   dropped onto this file open in it directly. No admin rights, no
echo   internet needed. Copy PDF-OCR.exe to any Windows PC and it just runs.
echo   The builder stays here in case you ever want to build again: --rebuild
echo ==========================================================================
echo   finished %DATE% %TIME%
echo.
echo   Press any key to open PDF-OCR, or just close this window.
pause >nul
if not defined DROPPED goto :ask_open
start "" "%~dp0PDF-OCR.exe"%DROPPED%
exit /b 0
:ask_open
start "" "%~dp0PDF-OCR.exe"
exit /b 0

:keep_build
echo   build files kept in "%W%"
goto :eof

:check_ok
echo.
echo ==========================================================================
echo   CHECK PASSED.  Python, Tesseract and the program source are all in order.
echo   Run this file again without --check to build PDF-OCR.exe.
echo ==========================================================================
pause
exit /b 0

rem ==========================================================================
rem  subroutines
rem ==========================================================================

:launch
if not defined DROPPED goto :launch_plain
start "" "%~dp0PDF-OCR.exe"%DROPPED%
exit /b 0
:launch_plain
start "" "%~dp0PDF-OCR.exe"
exit /b 0

:findpython
set "PYFOUND="
for /f "delims=" %%P in ('py -3 -c "import sys;print(sys.executable)" 2^>nul') do if not defined PYFOUND set "PYFOUND=%%P"
if not defined PYFOUND for /f "delims=" %%P in ('python -c "import sys;print(sys.executable)" 2^>nul') do if not defined PYFOUND set "PYFOUND=%%P"
if not defined PYFOUND for %%P in ("%LOCALAPPDATA%\Programs\Python\Python313\python.exe" "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" "%LOCALAPPDATA%\Programs\Python\Python310\python.exe" "%ProgramFiles%\Python313\python.exe" "%ProgramFiles%\Python312\python.exe" "%ProgramFiles%\Python311\python.exe") do if exist "%%~P" if not defined PYFOUND set "PYFOUND=%%~P"
if not defined PYFOUND exit /b 0
"%PYFOUND%" -c "import tkinter" >nul 2>&1
if errorlevel 1 set "PYFOUND="
exit /b 0

:findtess
set "TESSDIR="
if exist "%~dp0tesseract\tesseract.exe" set "TESSDIR=%~dp0tesseract"
if not defined TESSDIR if exist "%ProgramFiles%\Tesseract-OCR\tesseract.exe" set "TESSDIR=%ProgramFiles%\Tesseract-OCR"
if not defined TESSDIR if exist "%ProgramFiles(x86)%\Tesseract-OCR\tesseract.exe" set "TESSDIR=%ProgramFiles(x86)%\Tesseract-OCR"
if not defined TESSDIR if exist "%LOCALAPPDATA%\Programs\Tesseract-OCR\tesseract.exe" set "TESSDIR=%LOCALAPPDATA%\Programs\Tesseract-OCR"
if not defined TESSDIR if exist "%LOCALAPPDATA%\Tesseract-OCR\tesseract.exe" set "TESSDIR=%LOCALAPPDATA%\Tesseract-OCR"
if not defined TESSDIR for /f "delims=" %%F in ('where tesseract.exe 2^>nul') do if not defined TESSDIR set "TESSDIR=%%~dpF"
if defined TESSDIR if "%TESSDIR:~-1%"=="\" set "TESSDIR=%TESSDIR:~0,-1%"
exit /b 0

:portabletess
set "TESSDIR="
if not exist "%W%\tess-setup.exe" (
  echo       downloading Tesseract - it is only unpacked, never installed
  call :fetch "https://github.com/UB-Mannheim/tesseract/releases/download/v5.4.0.20240606/tesseract-ocr-w64-setup-5.4.0.20240606.exe" "%W%\tess-setup.exe"
  call :big "%W%\tess-setup.exe" 20000000
  if errorlevel 1 (
    call :fetch "https://digi.bib.uni-mannheim.de/tesseract/tesseract-ocr-w64-setup-5.5.3.20260724.exe" "%W%\tess-setup.exe"
    call :big "%W%\tess-setup.exe" 20000000
  )
)
call :big "%W%\tess-setup.exe" 20000000
if errorlevel 1 exit /b 1
if not exist "%W%\7z.msi" (
  for %%V in (2606 2501 2408 2301) do if not exist "%W%\7z.msi" call :fetch "https://www.7-zip.org/a/7z%%V-x64.msi" "%W%\7z.msi"
)
call :big "%W%\7z.msi" 1000000
if errorlevel 1 exit /b 1
if not exist "%W%\7zip" start /wait "" msiexec.exe /a "%W%\7z.msi" /qn TARGETDIR="%W%\7zip"
set "SZ="
set /a TRIES=0
:find7z
for /f "delims=" %%F in ('dir /b /s "%W%\7zip\7z.exe" 2^>nul') do set "SZ=%%F"
if defined SZ goto :got7z
set /a TRIES=%TRIES%+1
if %TRIES% GEQ 40 goto :got7z
ping -n 2 127.0.0.1 >nul
goto :find7z
:got7z
if not defined SZ exit /b 1
"%SZ%" x "%W%\tess-setup.exe" -o"%W%\payload" -y >nul 2>&1
if not exist "%W%\payload\tesseract.exe" exit /b 1
set "TESSDIR=%W%\payload"
exit /b 0

:fetch
if exist "%~2" del /f /q "%~2" >nul 2>&1
if defined CURL (
  "%CURL%" -L -f -s -S --retry 2 --retry-delay 2 --connect-timeout 20 --max-time 1200 -o "%~2" "%~1" >nul 2>&1
  exit /b 0
)
for %%P in (powershell.exe) do if not "%%~$PATH:P"=="" "%%~$PATH:P" -NoProfile -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '%~1' -OutFile '%~2' -TimeoutSec 1200 } catch { exit 1 }" >nul 2>&1
exit /b 0

:big
if not exist "%~1" exit /b 1
for %%A in ("%~1") do if %%~zA GEQ %~2 exit /b 0
exit /b 1

:small
if not exist "%~1" exit /b 1
for %%A in ("%~1") do if %%~zA LSS %~2 exit /b 0
exit /b 1

:checkpy
"%PYFOUND%" -c "import ast,sys; ast.parse(open(sys.argv[1],'rb').read().decode('utf-8','replace'))" "%~1" >nul 2>&1
if not errorlevel 1 exit /b 0
echo       extracting the program with the PowerShell fallback
for %%P in (powershell.exe) do if not "%%~$PATH:P"=="" "%%~$PATH:P" -NoProfile -ExecutionPolicy Bypass -Command "$l=[IO.File]::ReadAllLines('%~f0'); $i=-1; for($k=0;$k -lt $l.Count;$k++){ if($l[$k].Trim() -eq '#===PY_START==='){$i=$k; break} }; if($i -lt 0){exit 1}; [IO.File]::WriteAllLines('%~1',$l[($i+1)..($l.Count-1)],(New-Object Text.UTF8Encoding $false))" >nul 2>&1
"%PYFOUND%" -c "import ast,sys; ast.parse(open(sys.argv[1],'rb').read().decode('utf-8','replace'))" "%~1" >nul 2>&1
exit /b %errorlevel%

:getmodel
set "MDL=%W%\tesseract\tessdata\%1.traineddata"
if exist "%MDL%" exit /b 0
if not exist "%TESSDIR%\tessdata\%1.traineddata" goto :gmdl_dl
if /i "%REPO%"=="tessdata_best" goto :gmdl_dl
call :small "%TESSDIR%\tessdata\%1.traineddata" 6000000
if errorlevel 1 goto :gmdl_dl
copy /y "%TESSDIR%\tessdata\%1.traineddata" "%MDL%" >nul 2>&1
if exist "%MDL%" exit /b 0
:gmdl_dl
echo         model %1
call :fetch "https://raw.githubusercontent.com/tesseract-ocr/%REPO%/main/%1.traineddata" "%MDL%"
call :big "%MDL%" 100000
if not errorlevel 1 goto :gmdl_ok
call :fetch "https://github.com/tesseract-ocr/%REPO%/raw/main/%1.traineddata" "%MDL%"
call :big "%MDL%" 100000
if not errorlevel 1 goto :gmdl_ok
call :fetch "https://cdn.jsdelivr.net/gh/tesseract-ocr/%REPO%@main/%1.traineddata" "%MDL%"
call :big "%MDL%" 100000
if not errorlevel 1 goto :gmdl_ok
set "MODELFAIL=%MODELFAIL% %1"
exit /b 1
:gmdl_ok
set /a MODELCOUNT=%MODELCOUNT%+1
exit /b 0

rem ==========================================================================
rem  problems - each one tells the user what to do next
rem ==========================================================================

:err_work
echo.
echo   PROBLEM: this file cannot create a folder here:
echo            %~dp0
echo   Please copy this file to a writable place, for example the Desktop,
echo   and run it there again. Nothing was changed on this PC.
echo   The temporary folder was kept so you can look at it: %W%
pause
exit /b 1

:err_pydl
echo.
echo   PROBLEM: Python could not be downloaded. The PC seems to be offline.
echo   Please connect to the internet and run this file again.
echo   The temporary folder was kept so you can look at it: %W%
pause
exit /b 1

:err_nopython
echo.
echo   PROBLEM: Python with tkinter was not found on this PC.
echo   Install the free Python 3.12 from python.org - during setup tick
echo   "Add python.exe to PATH" and keep "tcl/tk" enabled - then run this
echo   file again. Nothing was changed on this PC.
pause
exit /b 1

:err_pip
echo.
echo   PROBLEM: the Python packages PyMuPDF and PyInstaller could not be
echo   installed. Please connect to the internet and run this file again.
echo   If it keeps failing, run this by hand in a command window:
echo     python -m pip install --user pymupdf pyinstaller
pause
exit /b 1

:err_notess
echo.
echo   PROBLEM: the OCR engine Tesseract could not be found or unpacked.
echo   Either connect to the internet and run this file again, or install
echo   the free "Tesseract OCR" from UB Mannheim and run this file again.
echo   The temporary folder was kept so you can look at it: %W%
pause
exit /b 1

:err_engine
echo.
echo   PROBLEM: Tesseract was found but its files could not be copied.
echo   Source folder: %TESSDIR%
echo   If that folder is protected, install Tesseract for this user only or
echo   let this file download a portable copy by removing the folder above.
pause
exit /b 1

:err_lang
echo.
echo   PROBLEM: these language models could not be downloaded:%MODELFAIL%
echo   Please check the internet connection and run this file again.
echo   Everything else is already prepared, so the next run is quick.
pause
exit /b 1

:err_write
echo.
echo   PROBLEM: the program part of this file could not be extracted.
echo   Please save this file as "Create-PDF-OCR.bat" - not as .txt - and
echo   make sure no antivirus program is blocking it, then try again.
pause
exit /b 1

:err_build
echo.
echo   PROBLEM: PyInstaller could not build the exe.
echo   The build log is here: %W%\build.log
echo   Please open it and send the last lines to the author.
pause
exit /b 1

:err_copy
echo.
echo   PROBLEM: PDF-OCR.exe was built but could not be copied here:
echo            %~dp0
echo   The finished exe is here and works from there as well:
echo            %W%\dist\PDF-OCR.exe
pause
exit /b 1

:warn_selftest
echo.
echo   WARNING: the new exe did not pass every check - see the report above.
echo   It was copied anyway, please try it. The report stays here:
echo            %REPORT%
echo.
copy /y "%W%\dist\PDF-OCR.exe" "%~dp0PDF-OCR.exe" >nul 2>&1
if exist "%~dp0PDF-OCR.exe" echo   PDF-OCR.exe is ready next to this file.
pause
exit /b 0

#===PY_START===
# -*- coding: ascii -*-
"""PDF-OCR 2.0 - portable, fast and accurate OCR for PDF files.

This program lives inside Create-PDF-OCR.bat: the builder extracts the text
after the marker line, writes it to pdfocr.py and freezes it into a single
PDF-OCR.exe with PyInstaller.

Design goals
  * portable  - one .exe, no installs, no registry, no internet at run time
  * fast      - every page is OCR'd in parallel by its own Tesseract process
  * accurate  - LSTM engine, smart dpi, existing text layers are preserved
  * reliable  - atomic output, per page retry, cancel kills child processes
Nothing here needs administrator rights.
"""
import os
import re
import sys
import time
import queue
import shutil
import tarfile
import tempfile
import threading
import subprocess
import traceback
from concurrent.futures import ThreadPoolExecutor, as_completed

try:                                     # PyMuPDF 1.24+ / 2.x
    import pymupdf
except Exception:                         # pragma: no cover
    import fitz as pymupdf

import tkinter as tk
from tkinter import ttk, filedialog, messagebox

APP = "PDF OCR"
VERSION = "2.0"
CREATOR = "Made by Junead Mansoori"
NOWIN = 0x08000000 if os.name == "nt" else 0
CANCEL_TIMEOUT = 5.0

# ---------------------------------------------------------------- languages
# (display name, tesseract code).  The builder only downloads the codes that
# are listed here, so a shorter list makes a smaller .exe.
LANGS = [
    ("English", "eng"),
    ("Hindi", "hin"),
    ("Marathi", "mar"),
    ("Arabic", "ara"),
    ("Russian", "rus"),
    ("Chinese (Simplified)", "chi_sim"),
    ("Japanese", "jpn"),
    ("Spanish", "spa"),
]

PRESETS = [
    ("All", None),
    ("None", []),
]

QUALITIES = [
    ("Auto - best balance (recommended)", "auto"),
    ("Fast - 200 dpi", "200"),
    ("Balanced - 300 dpi", "300"),
    ("Maximum detail - 400 dpi", "400"),
]


# ---------------------------------------------------------------- utilities


def app_dir():
    """Folder the .exe (or this script) lives in - stays portable."""
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.executable))
    return os.path.dirname(os.path.abspath(__file__))


def res_dir():
    """Folder that holds the bundled tesseract folder."""
    return getattr(sys, "_MEIPASS", None) or app_dir()


def safe_out(msg):
    """Windowed .exe files have no stdout - never crash on a diagnostic."""
    for stream in (sys.__stdout__, sys.stderr):
        try:
            if stream is not None:
                stream.write(str(msg) + "\n")
                stream.flush()
                return
        except Exception:
            pass


def engine_cache_needed():
    """True when a packed engine has to be unpacked before the first use."""
    for folder in (res_dir(), app_dir()):
        archive = os.path.join(folder, ENGINE_ARCHIVE)
        if not os.path.isfile(archive):
            continue
        if not os.path.isfile(os.path.join(engine_cache_dir(), "engine",
                                           "tesseract.exe")):
            return True
    return False


ENGINE_ARCHIVE = "tesseract.tar.xz"      # engine packed by the builder


def engine_cache_dir():
    base = os.environ.get("LOCALAPPDATA") or tempfile.gettempdir()
    return os.path.join(base, "PDF-OCR")


def ensure_engine(log=None):
    """Return a folder holding tesseract.exe, or None.

    The compact build packs the whole engine into one xz archive inside the
    exe; it is unpacked once into a cache folder and reused from then on, so
    every later start is quick and the exe stays small.
    """
    for folder in (os.path.join(res_dir(), ENGINE_ARCHIVE),
                   os.path.join(app_dir(), ENGINE_ARCHIVE)):
        if not os.path.isfile(folder):
            continue
        archive = folder
        target = os.path.join(engine_cache_dir(), "engine")
        stamp = os.path.join(engine_cache_dir(), "engine.txt")
        try:
            signature = "%d-%d" % (os.path.getsize(archive),
                                   int(os.path.getmtime(archive)))
        except OSError:
            signature = ""
        if os.path.isfile(os.path.join(target, "tesseract.exe")):
            try:
                with open(stamp, "r", encoding="utf-8") as handle:
                    if handle.read().strip() == signature:
                        return target
            except OSError:
                pass
        try:
            if log is not None:
                log.add("unpacking the OCR engine once, please wait ...")
            os.makedirs(target, exist_ok=True)
            with tarfile.open(archive, "r:xz") as tar:
                try:
                    tar.extractall(target, filter="data")
                except TypeError:            # python < 3.11.4
                    tar.extractall(target)
            if not os.path.isfile(os.path.join(target, "tesseract.exe")):
                return None
            try:
                with open(stamp, "w", encoding="utf-8") as handle:
                    handle.write(signature)
            except OSError:
                pass
            return target
        except Exception as exc:
            if log is not None:
                log.add("could not unpack the engine: %s" % exc)
            return None
    return None


class RunLog(object):
    """Human readable messages for the UI and for the log file."""

    def __init__(self):
        self.lines = []
        self.lock = threading.Lock()

    def add(self, msg):
        stamp = time.strftime("%H:%M:%S")
        line = "[%s] %s" % (stamp, msg)
        with self.lock:
            self.lines.append(line)
        return line

    def text(self):
        with self.lock:
            return "\n".join(self.lines)


def human_time(seconds):
    if seconds is None or seconds != seconds or seconds < 0:
        return "--:--"
    seconds = int(seconds)
    if seconds >= 3600:
        return "%d:%02d:%02d" % (seconds // 3600, (seconds % 3600) // 60,
                                 seconds % 60)
    return "%d:%02d" % (seconds // 60, seconds % 60)


def find_tesseract():
    """Return (tesseract.exe, tessdata dir) or (None, None).

    Order matters: the engine that belongs to this program wins over a
    Tesseract that happens to be installed on the PC, otherwise a PC with an
    old installation (few languages) would silently replace the bundled one.
    """
    for root in (os.path.join(app_dir(), "tesseract"), res_dir(),
                 os.path.join(res_dir(), "tesseract")):
        for sub in ("", "tesseract"):
            exe = os.path.join(root, sub, "tesseract.exe")
            if os.path.isfile(exe):
                return exe, os.path.join(root, sub, "tessdata")
    packed = ensure_engine()                  # compact build: engine in the exe
    if packed:
        return (os.path.join(packed, "tesseract.exe"),
                os.path.join(packed, "tessdata"))
    if os.name == "nt":
        for env in ("ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA"):
            root = os.environ.get(env)
            if not root:
                continue
            for name in ("Tesseract-OCR", os.path.join("Programs",
                                                       "Tesseract-OCR")):
                exe = os.path.join(root, name, "tesseract.exe")
                if os.path.isfile(exe):
                    return exe, os.path.join(root, name, "tessdata")
    exe = shutil.which("tesseract")
    if exe:
        return exe, os.path.join(os.path.dirname(exe), "tessdata")
    return None, None


def available_langs(tessdata):
    """Language codes that really have a model next to the engine."""
    found = []
    if tessdata and os.path.isdir(tessdata):
        for name in sorted(os.listdir(tessdata)):
            if name.lower().endswith(".traineddata"):
                found.append(name[:-len(".traineddata")])
    return found


def unique_path(base, ext=".pdf"):
    path = base + ext
    if not os.path.exists(path):
        return path
    n = 2
    while os.path.exists("%s-%d%s" % (base, n, ext)):
        n += 1
    return "%s-%d%s" % (base, n, ext)


CROP_DPI = 60           # resolution of the cheap first look at a page


def probe_page(page, dpi=CROP_DPI, dark=200, pad_pt=6.0):
    """One cheap low resolution look at a page.

    Returns (blank, ink_box_in_points, text_line_height_in_points).
    Used to skip blank pages early and to measure how big the text is, so
    the OCR resolution can be chosen instead of guessed.
    """
    try:
        pix = page.get_pixmap(dpi=dpi, colorspace=GRAY, alpha=False)
    except Exception:
        return False, None, 0.0
    height = pix.height
    width = pix.width
    mask = pix.samples.translate(
        bytes(1 if value < dark else 0 for value in range(256)))
    top = bottom = None
    left = width
    right = 0
    runs = []
    run_start = None
    for row in range(height):
        line = mask[row * width:(row + 1) * width]
        first = line.find(b"\x01")
        if first < 0:
            if run_start is not None:
                runs.append(row - run_start)
                run_start = None
            continue
        last = line.rfind(b"\x01")
        if run_start is None:
            run_start = row
        if top is None:
            top = row
        bottom = row
        if first < left:
            left = first
        if last > right:
            right = last
    if run_start is not None:
        runs.append(height - run_start)
    del pix
    if top is None:
        return True, None, 0.0
    scale = 72.0 / dpi
    origin = page.rect
    box = pymupdf.Rect(origin.x0 + left * scale - pad_pt,
                       origin.y0 + top * scale - pad_pt,
                       origin.x0 + right * scale + pad_pt,
                       origin.y0 + bottom * scale + pad_pt)
    box &= origin
    useful = sorted(run for run in runs if run >= 2)
    line_pt = 0.0
    if useful:
        line_pt = useful[len(useful) // 2] * scale
    return False, box, line_pt


def trim_clip(box, page_rect, keep=0.90):
    """Only crop when it really saves work, otherwise render the whole page."""
    if box is None:
        return None
    area = box.width * box.height
    whole = page_rect.width * page_rect.height
    if whole <= 0 or area <= 0 or area > whole * keep:
        return None
    return box


def pick_dpi(quality, rect, line_pt=0.0):
    """Turn the quality setting, the page size and the measured text height
    into a sensible dpi value.

    Tesseract's LSTM engine likes characters of roughly 30 pixels height, so
    when the probe managed to measure the text, that is what is used: small
    print gets a high dpi, big print a low one - and both are fast.
    """
    long_pt = max(rect.width, rect.height, 1.0)
    if quality == "auto":
        if line_pt > 1.5:
            dpi = int(round(30.0 * 72.0 / line_pt))
        else:
            dpi = int(round(3200.0 * 72.0 / long_pt))
        dpi = min(max(dpi, 180), 500)
    else:
        dpi = int(quality)
    # never render silly big bitmaps (tesseract gets slow / runs out of ram)
    limit = 4600.0
    if long_pt * dpi / 72.0 > limit:
        dpi = max(150, int(limit * 72.0 / long_pt))
    return dpi


GRAY = getattr(pymupdf, "csGRAY", None) or "gray"


def is_blank(pix, threshold=0.0015):
    """True when the rendered page has almost no dark pixels."""
    try:
        raw = pix.samples
    except Exception:
        return False
    if not raw:
        return True
    step = max(1, len(raw) // 250000)
    sample = raw[::step]
    table = bytes([1 if v < 200 else 0 for v in range(256)])
    dark = sum(sample.translate(table))
    return (dark / float(len(sample))) < threshold


def count_text(pdf_bytes):
    """How many characters the OCR result actually contains."""
    try:
        doc = pymupdf.open(stream=pdf_bytes, filetype="pdf")
        try:
            text = doc[0].get_text("text")
        finally:
            doc.close()
        return len(text.replace(" ", "").strip())
    except Exception:
        return 0


def read_tsv_confidence(path):
    """Average word confidence (0..100) of a tesseract TSV report, or -1."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return -1.0
    scores = []
    for line in lines[1:]:
        parts = line.split("\t")
        if len(parts) < 12 or not parts[11].strip():
            continue
        try:
            confidence = float(parts[10])
        except ValueError:
            continue
        if confidence >= 0:
            scores.append(confidence)
    if not scores:
        return -1.0
    return sum(scores) / float(len(scores))


class Settings(object):
    """Everything the worker threads need to know."""

    def __init__(self):
        self.langs = "eng"
        self.quality = "auto"
        self.skip_text = True
        self.skip_blank = True
        self.split_mode = "none"
        self.split_value = 50
        self.write_txt = False
        self.outdir = ""
        self.psm = 3
        self.workers = 0          # 0 = choose automatically
        self.pages_per_call = 0   # 0 = one tesseract call per page
        self.crop = True          # leave the empty margins out of the OCR

    def describe(self):
        split = "no split"
        if self.split_mode == "pages":
            split = "%s pages per file" % int(self.split_value)
        elif self.split_mode == "size":
            split = "%s MB per file" % self.split_value
        return "langs=%s quality=%s split=%s" % (self.langs, self.quality,
                                                 split)


def physical_cores():
    """Number of real CPU cores (Windows), fallback = logical cores.

    Running more Tesseract processes than there are real cores makes every one
    of them slower, so this matters for speed.
    """
    logical = os.cpu_count() or 1
    if os.name != "nt":
        return logical
    try:
        import ctypes
        from ctypes import wintypes
        size = wintypes.DWORD(0)
        kernel32 = ctypes.windll.kernel32
        kernel32.GetLogicalProcessorInformation(None, ctypes.byref(size))
        if not size.value:
            return logical
        buffer = ctypes.create_string_buffer(size.value)
        if not kernel32.GetLogicalProcessorInformation(buffer,
                                                       ctypes.byref(size)):
            return logical
        entry_size = 24 if ctypes.sizeof(ctypes.c_void_p) == 8 else 16
        cores = 0
        for index in range(size.value // entry_size):
            entry = buffer.raw[index * entry_size:(index + 1) * entry_size]
            relationship = int.from_bytes(entry[8:12], "little")
            if relationship == 0:              # RelationProcessorCore
                cores += 1
        return cores or logical
    except Exception:
        return logical


def available_memory_mb():
    """Free physical memory in MB (Windows), 0 when it cannot be read."""
    if os.name != "nt":
        return 0
    try:
        import ctypes
        class Memory(ctypes.Structure):
            _fields_ = [("dwLength", ctypes.c_ulong),
                        ("dwMemoryLoad", ctypes.c_ulong),
                        ("ullTotalPhys", ctypes.c_ulonglong),
                        ("ullAvailPhys", ctypes.c_ulonglong),
                        ("ullTotalPageFile", ctypes.c_ulonglong),
                        ("ullAvailPageFile", ctypes.c_ulonglong),
                        ("ullTotalVirtual", ctypes.c_ulonglong),
                        ("ullAvailVirtual", ctypes.c_ulonglong),
                        ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]
        status = Memory()
        status.dwLength = ctypes.sizeof(Memory)
        if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
            return int(status.ullAvailPhys / 1048576)
    except Exception:
        pass
    return 0


def auto_workers(total):
    """How many Tesseract processes to run at once.

    Measured on this PC: using all logical cores is fastest. Each Tesseract
    process can want a few hundred MB on a big page, so the number is also
    capped by the free memory.
    """
    logical = os.cpu_count() or 1
    free_mb = available_memory_mb()
    workers = logical
    if free_mb:
        workers = min(workers, max(1, int(free_mb / 450)))
    if logical <= 2:
        workers = max(1, logical)
    return max(1, min(workers, 16, max(1, total)))


class TessRunner(object):
    """Runs tesseract: one process per page, no deadlocks, killable."""

    def __init__(self, exe, tessdata, log, psm=3):
        self.exe = exe
        self.tessdata = tessdata or ""
        self.log = log
        self.psm = int(psm or 3)
        self.env = dict(os.environ)
        self.env["OMP_THREAD_LIMIT"] = "1"      # one process per cpu core
        self.env["OMP_NUM_THREADS"] = "1"
        self.env["OMP_WAIT_POLICY"] = "PASSIVE"
        if self.tessdata:
            self.env["TESSDATA_PREFIX"] = self.tessdata
        for key in ("PYTHONHOME", "PYTHONPATH", "TCL_LIBRARY", "TK_LIBRARY",
                    "PYTHONSTARTUP"):
            self.env.pop(key, None)
        self.procs = set()
        self.lock = threading.Lock()

    def _capture(self, args, timeout=60):
        try:
            done = subprocess.run(args, stdin=subprocess.DEVNULL,
                                  stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT,
                                  creationflags=NOWIN, env=self.env,
                                  timeout=timeout)
            return done.returncode, done.stdout.decode("utf8", "replace")
        except Exception as exc:
            return 1, "%s" % exc

    def version(self):
        code, out = self._capture([self.exe, "--version"])
        first = out.strip().splitlines()[0].strip() if out.strip() else "?"
        return first

    def languages(self):
        code, out = self._capture([self.exe, "--list-langs",
                                   "--tessdata-dir", self.tessdata], 120)
        langs = []
        for line in out.splitlines():
            line = line.strip()
            if line and not line.startswith("List of") and " " not in line:
                langs.append(line)
        return langs

    def _kill(self, proc):
        try:
            proc.kill()
        except Exception:
            pass

    def kill_all(self):
        with self.lock:
            procs = list(self.procs)
        for proc in procs:
            self._kill(proc)

    def run(self, image, base, lang, dpi, cancel, timeout=1800.0,
            want_tsv=False):
        """OCR one image file.  Returns (ok, note, mean_confidence)."""
        args = [self.exe, image, base, "-l", lang, "--dpi", str(dpi),
                "--oem", "1", "--psm", str(self.psm),
                "-c", "textonly_pdf=1",
                "-c", "preserve_interword_spaces=1",
                "-c", "tessedit_create_pdf=1"]
        if want_tsv:
            args += ["-c", "tessedit_create_tsv=1"]
        if self.tessdata:
            args += ["--tessdata-dir", self.tessdata]
        args.append("pdf")
        errlog = base + ".err"
        status = 0
        with open(errlog, "wb") as handle:
            try:
                proc = subprocess.Popen(args, stdin=subprocess.DEVNULL,
                                        stdout=handle, stderr=subprocess.STDOUT,
                                        creationflags=NOWIN, env=self.env)
            except Exception as exc:
                return False, "could not start tesseract: %s" % exc, -1.0
            with self.lock:
                self.procs.add(proc)
            started = time.time()
            while True:
                code = proc.poll()
                if code is not None:
                    status = code
                    break
                if cancel.is_set():
                    self._kill(proc)
                    status = -2
                    break
                if time.time() - started > timeout:
                    self._kill(proc)
                    status = -3
                    break
                time.sleep(0.05)
            with self.lock:
                self.procs.discard(proc)
        note = self._tail(errlog)
        if status == -2:
            return False, "cancelled", -1.0
        if status == -3:
            return False, "timed out after %d s" % int(timeout), -1.0
        if status != 0:
            return False, note or ("tesseract exit code %d" % status), -1.0
        if not os.path.isfile(base + ".pdf"):
            return False, note or "tesseract produced no output", -1.0
        confidence = read_tsv_confidence(base + ".tsv") if want_tsv else -1.0
        return True, note, confidence

    @staticmethod
    def _tail(path):
        try:
            with open(path, "rb") as handle:
                data = handle.read()
        except OSError:
            return ""
        text = data.decode("utf8", "replace")
        keep = [line for line in text.splitlines() if line.strip()]
        bad = [line for line in keep
               if "error" in line.lower() or "warning" in line.lower()]
        return " ".join((bad or keep)[-3:])[:400]


# ------------------------------------------------------------- page pipeline


def process_file(path, cfg, cancel, runner, log, progress):
    """OCR one PDF.  Returns (list_of_new_files, stats) or (None, stats)."""
    name = os.path.basename(path)
    stats = {"pages": 0, "ocr": 0, "text": 0, "blank": 0, "failed": 0}
    doc = pymupdf.open(path)
    try:
        if doc.needs_pass and not doc.is_authenticated:
            raise RuntimeError("needs a password")
        total = doc.page_count
        stats["pages"] = total
        if total == 0:
            raise RuntimeError("no pages")
        tmp = tempfile.mkdtemp(prefix="pdfocr_")
        lock = threading.Lock()
        results = {}
        placements = {}
        clips = {}
        try:
            def attempt(index, rot, visible, scale=1.0, want_tsv=False):
                """Render one page and OCR it.

                visible=True renders the page the way a reader displays it
                (where the text stands upright for a well made file).

                A cheap 60 dpi probe comes first: it finds blank pages without
                rendering them at full size, it measures how tall the text is
                (which decides the dpi) and it gives the area that actually
                carries ink, so the empty margins are not OCR'd at all.

                Returns (ok, note, kind, data, chars, dpi, confidence).
                """
                clip = None
                with lock:
                    page = doc[index]
                    box = page.rect if visible else pymupdf.Rect(page.mediabox)
                    blank, ink, line_pt = probe_page(page, CROP_DPI)
                    if blank and cfg.skip_blank:
                        return True, "blank", "blank", None, 0, 0, -1.0
                    dpi = pick_dpi(cfg.quality, box, line_pt)
                    if cfg.crop and not rot:
                        clip = trim_clip(ink, box)
                    dpi = max(150, int(dpi * scale))
                    if rot and not visible:
                        page.set_rotation(0)          # look at the raw pixels
                    try:
                        pix = page.get_pixmap(dpi=dpi, colorspace=GRAY,
                                              alpha=False, clip=clip)
                    finally:
                        if rot and not visible:
                            page.set_rotation(rot)
                    if cfg.skip_blank and is_blank(pix):
                        return True, "blank", "blank", None, 0, dpi, -1.0
                png = os.path.join(tmp, "p%04d.png" % index)
                base = os.path.join(tmp, "p%04d" % index)
                with open(png, "wb") as handle:
                    handle.write(pix.tobytes("png"))
                del pix
                ok, note, confidence = runner.run(png, base, cfg.langs, dpi,
                                                  cancel, timeout=1800.0,
                                                  want_tsv=want_tsv)
                if not ok:
                    kind = "cancelled" if note == "cancelled" else "failed"
                    return False, note, kind, None, 0, dpi, -1.0
                try:
                    with open(base + ".pdf", "rb") as handle:
                        data = handle.read()
                except OSError as exc:
                    return False, "%s" % exc, "failed", None, 0, dpi, -1.0
                if clip is not None:
                    clips[index] = clip
                return True, note, "ocr", data, count_text(data), dpi, confidence

            def job(index):
                if cancel.is_set():
                    return index, None, "cancelled"
                with lock:
                    page = doc[index]
                    rot = page.rotation
                    if cfg.skip_text and page.get_text("text").strip():
                        return index, None, "text"
                # how the finished text layer has to be turned so that it
                # sits on the page content instead of on the shown page
                # (measured: the rotate value equals the page rotation)
                orientation = rot
                ok, note, kind, data, chars, dpi, conf = attempt(
                    index, rot, True, want_tsv=bool(rot))
                if kind in ("cancelled", "blank"):
                    return index, None, kind
                if not ok:
                    log.add("  page %d: retrying smaller (%s)"
                            % (index + 1, note))
                    ok, note, kind, data, chars, dpi, conf = attempt(
                        index, rot, True, 0.6, want_tsv=bool(rot))
                if not ok:
                    return index, None, "failed: %s" % note
                if rot and conf < 65 and not cancel.is_set():
                    # rotated pages come in two flavours: sometimes the raw
                    # pixels are the upright ones - let tesseract judge
                    log.add("  page %d: rotation %d reads badly (%d%% "
                            "confidence), trying the raw orientation"
                            % (index + 1, rot, int(conf if conf > 0 else 0)))
                    ok2, _n2, _k2, data2, chars2, _d2, conf2 = attempt(
                        index, rot, False, want_tsv=True)
                    if ok2 and conf2 > conf + 3:
                        data, chars, conf = data2, chars2, conf2
                        orientation = 0
                        log.add("  page %d: using the raw orientation (%d%%)"
                                % (index + 1, int(conf2)))
                placements[index] = orientation
                return index, data, "ocr"

            workers = cfg.workers or auto_workers(total)
            workers = max(1, min(workers, max(1, total)))
            log.add("  %s: %d page(s)" % (name, total))
            with ThreadPoolExecutor(max_workers=workers) as pool:
                futures = [pool.submit(job, i) for i in range(total)]
                for future in as_completed(futures):
                    try:
                        index, data, kind = future.result()
                    except Exception as exc:
                        stats["failed"] += 1
                        log.add("  page: internal error: %s" % exc)
                        progress(1)
                        continue
                    if data:
                        results[index] = data
                    if kind == "ocr":
                        stats["ocr"] += 1
                    elif kind == "text":
                        stats["text"] += 1
                    elif kind == "blank":
                        stats["blank"] += 1
                    elif kind == "cancelled":
                        pass
                    else:
                        stats["failed"] += 1
                        log.add("  page %d: %s" % (index + 1, kind))
                    progress(1)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

        if cancel.is_set():
            return None, stats

        log.add("  merging text layer into %d page(s)" % len(results))
        for index in range(total):
            data = results.get(index)
            if not data:
                continue
            page = doc[index]
            src = pymupdf.open(stream=data, filetype="pdf")
            try:
                rect = clips.get(index)
                if rect is None:
                    rect = pymupdf.Rect(page.mediabox)
                page.show_pdf_page(rect, src, 0, overlay=True,
                                   rotate=placements.get(index, 0))
            finally:
                src.close()
        results.clear()
        placements.clear()
        clips.clear()

        stem = os.path.splitext(name)[0] + "_ocr"
        folder = cfg.outdir or os.path.dirname(path)
        if folder and not os.path.isdir(folder):
            os.makedirs(folder)
        base = os.path.join(folder, stem)
        log.add("  saving output")
        files = split_save(doc, base, cfg, cancel, log)
        if cfg.write_txt and files:
            write_text_files(files, log)
        return files, stats
    finally:
        doc.close()


# ---------------------------------------------------------------- output


def _save_doc(doc, path):
    """Write atomically so a crash can never leave a half finished file."""
    tmp = path + ".part"
    doc.save(tmp, garbage=3, deflate=True)
    if os.path.exists(path):
        os.remove(path)
    os.replace(tmp, path)
    return path


def split_save(doc, base, cfg, cancel, log):
    """Save the finished document, optionally split into several files."""
    total = doc.page_count
    files = []
    if cfg.split_mode == "none":
        files.append(_save_doc(doc, unique_path(base)))
        log.add("  wrote %s" % os.path.basename(files[-1]))
        return files
    if cfg.split_mode == "pages":
        step = max(1, int(cfg.split_value))
        groups = [(start, min(start + step, total) - 1)
                  for start in range(0, total, step)]
    else:
        limit = max(0.2, float(cfg.split_value)) * 1024.0 * 1024.0
        sizes = []
        for index in range(total):
            if cancel.is_set():
                return files
            one = pymupdf.open()
            one.insert_pdf(doc, from_page=index, to_page=index)
            sizes.append(max(1024, len(one.tobytes(garbage=3, deflate=True))))
            one.close()
        groups = []
        start = 0
        used = 0
        for index, size in enumerate(sizes):
            if used and used + size > limit and index > start:
                groups.append((start, index - 1))
                start = index
                used = 0
            used += size
        groups.append((start, total - 1))
    for number, (first, last) in enumerate(groups, 1):
        if cancel.is_set():
            break
        part = pymupdf.open()
        try:
            part.insert_pdf(doc, from_page=first, to_page=last)
            path = unique_path("%s_part%03d" % (base, number))
            files.append(_save_doc(part, path))
            log.add("  wrote %s (%d page(s))"
                    % (os.path.basename(files[-1]), last - first + 1))
        finally:
            part.close()
    return files


def write_text_files(files, log):
    """Plain .txt copy of the recognised text - no second OCR pass."""
    for path in files:
        try:
            doc = pymupdf.open(path)
            try:
                chunks = [page.get_text("text") for page in doc]
            finally:
                doc.close()
            txt = unique_path(os.path.splitext(path)[0], ".txt")
            body = "\n\n".join(chunk.strip() for chunk in chunks).strip()
            with open(txt, "w", encoding="utf-8", errors="replace") as handle:
                handle.write(body + "\n")
            log.add("  wrote %s" % os.path.basename(txt))
        except Exception as exc:
            log.add("  text export failed for %s: %s"
                    % (os.path.basename(path), exc))


# ------------------------------------------------------- build time helper


def _pe_imports(path):
    """Library names a Windows program imports (normal and delay loaded).

    Used by --collect-engine so the builder can ship exactly the libraries
    Tesseract needs instead of its whole folder.
    """
    import struct
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except OSError:
        return []
    if len(data) < 0x40 or data[:2] != b"MZ":
        return []
    offset = struct.unpack_from("<I", data, 0x3C)[0]
    if offset + 24 > len(data) or data[offset:offset + 4] != b"PE\0\0":
        return []
    coff = offset + 4
    sections_count = struct.unpack_from("<H", data, coff + 2)[0]
    optional_size = struct.unpack_from("<H", data, coff + 16)[0]
    optional = coff + 20
    magic = struct.unpack_from("<H", data, optional)[0]
    if magic == 0x20B:
        directories = optional + 112
    elif magic == 0x10B:
        directories = optional + 96
    else:
        return []
    sections = []
    table = optional + optional_size
    for index in range(sections_count):
        base = table + index * 40
        if base + 40 > len(data):
            break
        size = struct.unpack_from("<I", data, base + 8)[0]
        va = struct.unpack_from("<I", data, base + 12)[0]
        raw = struct.unpack_from("<I", data, base + 20)[0]
        sections.append((va, max(size, 1), raw))

    def to_offset(rva):
        for va, size, raw in sections:
            if va <= rva < va + size:
                return raw + (rva - va)
        return None

    names = []
    for which in (1, 13):               # 1 imports, 13 delay imports
        rva, size = struct.unpack_from("<II", data, directories + which * 8)
        if not rva or not size:
            continue
        start = to_offset(rva)
        if start is None:
            continue
        step = 8 if which == 13 else 20
        for index in range(max(1, size // step)):
            entry = start + index * step
            if entry + step > len(data):
                break
            if which == 13:
                name_rva = struct.unpack_from("<I", data, entry + 4)[0]
            else:
                # descriptor: original thunk, stamp, chain, name, thunk
                values = struct.unpack_from("<IIIII", data, entry)
                name_rva = values[3]
                if values[0] == 0 and name_rva == 0:
                    break
            if not name_rva:
                continue
            position = to_offset(name_rva)
            if position is None:
                continue
            end = data.find(b"\0", position)
            if end < 0:
                end = len(data)
            names.append(data[position:end].decode("ascii", "replace").lower())
    return names


def collect_engine(src, dst, log):
    """Copy tesseract.exe plus every library it imports, and the tessdata bits.

    Falls back to copying every library when the import tables cannot be read,
    so the result always works - it is only bigger in that rare case.
    """
    if not os.path.isfile(os.path.join(src, "tesseract.exe")):
        log.add("no tesseract.exe in %s" % src)
        return 1
    os.makedirs(os.path.join(dst, "tessdata", "configs"), exist_ok=True)
    wanted = []
    seen = set()
    queue = [os.path.join(src, "tesseract.exe")]
    while queue:
        current = queue.pop()
        wanted.append(current)
        for name in _pe_imports(current):
            if name in seen:
                continue
            seen.add(name)
            candidate = os.path.join(src, name)
            if os.path.isfile(candidate):
                queue.append(candidate)
    if len(wanted) < 3:                  # parsing failed - stay safe
        log.add("import table not readable, copying every library")
        wanted = [os.path.join(src, "tesseract.exe")]
        wanted += [os.path.join(src, n) for n in sorted(os.listdir(src))
                   if n.lower().endswith(".dll")]
    copied = 0
    for path in wanted:
        try:
            shutil.copy2(path, os.path.join(dst, os.path.basename(path)))
            copied += 1
        except OSError as exc:
            log.add("could not copy %s (%s)" % (os.path.basename(path), exc))
    for name in ("configs", "tessconfigs"):
        source = os.path.join(src, "tessdata", name)
        if os.path.isdir(source):
            target = os.path.join(dst, "tessdata", name)
            if os.path.isdir(target):
                shutil.rmtree(target, ignore_errors=True)
            shutil.copytree(source, target)
    for name in ("pdf.ttf", "eng.traineddata"):
        source = os.path.join(src, "tessdata", name)
        if os.path.isfile(source):
            shutil.copy2(source, os.path.join(dst, "tessdata", name))
    size = sum(os.path.getsize(os.path.join(dst, f))
               for f in os.listdir(dst) if os.path.isfile(os.path.join(dst, f)))
    log.add("collected %d file(s), %.1f MB of engine plus tessdata"
            % (copied, size / 1048576.0))
    return 0


def pack_engine(src, dest, log):
    """Pack an engine folder into one xz archive (used by the builder).

    xz keeps the 97 MB Tesseract library down to about 21 MB, which is what
    makes the single exe small.  The program unpacks it once on first use.
    """
    if not os.path.isfile(os.path.join(src, "tesseract.exe")):
        log.add("no tesseract.exe in %s" % src)
        return 1
    files = 0
    total = 0
    with tarfile.open(dest, "w:xz", preset=3) as tar:
        for root, _dirs, names in os.walk(src):
            for name in sorted(names):
                full = os.path.join(root, name)
                tar.add(full, arcname=os.path.relpath(full, src))
                files += 1
                total += os.path.getsize(full)
    log.add("packed %d file(s), %.1f MB into %.1f MB"
            % (files, total / 1048576.0, os.path.getsize(dest) / 1048576.0))
    return 0


# ---------------------------------------------------------------- self test


def selftest():
    """Head-less end to end check, used by the builder and by --selftest."""
    report = []
    failures = []

    def check(label, good, detail=""):
        report.append("%-5s %s%s" % ("OK" if good else "FAIL", label,
                                     ("   [" + detail + "]") if detail else ""))
        if not good:
            failures.append(label)

    report.append("%s %s self test" % (APP, VERSION))
    report.append("python  : %s (%s)"
                  % (sys.version.split()[0],
                     "frozen" if getattr(sys, "frozen", False) else "script"))
    report.append("pymupdf : %s" % getattr(pymupdf, "__version__", "?"))
    report.append("exe dir : %s" % app_dir())

    exe, tessdata = find_tesseract()
    check("tesseract engine found", bool(exe), str(exe))
    if not exe:
        report.append("result  : FAIL")
        return report, False

    runner = TessRunner(exe, tessdata, RunLog())
    version = runner.version()
    check("tesseract starts", "tesseract" in version.lower(), version[:80])
    report.append("engine  : %s" % version[:80])
    report.append("tessdata: %s" % tessdata)

    langs = runner.languages()
    expected = [code for _name, code in LANGS]
    missing = [code for code in expected if code not in langs]
    bundled = any(os.path.isfile(os.path.join(folder, ENGINE_ARCHIVE))
                  for folder in (res_dir(), app_dir()))
    report.append("source  : %s" % ("engine packed inside this exe"
                                    if bundled else "engine found on this PC"))
    if bundled:
        # the exe carries its own engine, so every model has to be in there
        check("all bundled languages present", not missing,
              ("missing " + ", ".join(missing)) if missing
              else "%d models" % len(langs))
    else:
        report.append("models  : %d of %d languages available%s"
                      % (len([code for code in expected if code in langs]),
                         len(expected),
                         ("   (missing " + ", ".join(missing) + ")")
                         if missing else ""))
    check("english model usable", "eng" in langs)

    if "eng" in langs:
        tmp = tempfile.mkdtemp(prefix="pdfocr_check_")
        try:
            doc = pymupdf.open()
            page = doc.new_page(width=595, height=842)
            page.insert_text((60, 120), "PDF OCR self test 123456",
                             fontsize=28)
            pix = page.get_pixmap(dpi=300, colorspace=GRAY, alpha=False)
            png = os.path.join(tmp, "probe.png")
            with open(png, "wb") as handle:
                handle.write(pix.tobytes("png"))
            del pix
            doc.close()
            good, note, _conf = runner.run(png, os.path.join(tmp, "probe"),
                                           "eng", 300, threading.Event(),
                                           timeout=300.0)
            check("ocr round trip", good, note)
            if good:
                with open(os.path.join(tmp, "probe.pdf"), "rb") as handle:
                    data = handle.read()
                out = pymupdf.open(stream=data, filetype="pdf")
                try:
                    text = out[0].get_text("text")
                    check("recognised text is searchable",
                          "123456" in text.replace(" ", ""),
                          text.strip()[:60])
                finally:
                    out.close()
        except Exception:
            check("ocr round trip", False,
                  traceback.format_exc(limit=2).strip().splitlines()[-1])
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    try:
        root = tk.Tk()
        root.withdraw()
        root.update_idletasks()
        root.destroy()
        check("graphical interface usable", True)
    except Exception as exc:
        check("graphical interface usable", False, str(exc))

    try:
        root = make_root()
        root.withdraw()
        window = Ui(root, [], {})
        window.status.configure(text="self test")
        root.update_idletasks()
        languages = len(window.lang_vars)
        root.destroy()
        check("main window builds", languages > 0, "%d languages offered"
              % languages)
    except Exception as exc:
        check("main window builds", False, str(exc).splitlines()[0][:120])

    report.append("result  : %s" % ("PASS" if not failures else "FAIL"))
    return report, not failures


def write_report(lines, name="PDF-OCR-selftest.txt"):
    """Save the self test report, next to the .exe when that is writable."""
    body = "\n".join(lines) + "\n"
    try:
        path = os.path.join(app_dir(), name)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(body)
        return path
    except OSError:
        path = os.path.join(tempfile.gettempdir(), name)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(body)
        return path


# --------------------------------------------------------------- interface

PALETTE = {
    "bg": "#0e141c",
    "card": "#172133",
    "card2": "#1f2b40",
    "line": "#2a3a55",
    "text": "#e9f0fa",
    "muted": "#94a6c0",
    "accent": "#41a8f7",
    "accent2": "#1e7fd0",
    "good": "#43c98b",
    "bad": "#ff6f6f",
    "warn": "#ffc46b",
}


def build_style(root):
    """A calm dark theme that still looks native and readable."""
    p = PALETTE
    fam = "Segoe UI"
    style = ttk.Style(root)
    try:
        style.theme_use("clam")
    except tk.TclError:
        pass
    style.configure(".", background=p["bg"], foreground=p["text"],
                    fieldbackground=p["card2"], font=(fam, 9))
    style.configure("TFrame", background=p["bg"])
    style.configure("Card.TFrame", background=p["card"])
    style.configure("TLabel", background=p["bg"], foreground=p["text"])
    style.configure("Card.TLabel", background=p["card"], foreground=p["text"])
    style.configure("Muted.Card.TLabel", background=p["card"],
                    foreground=p["muted"], font=(fam, 8))
    style.configure("Head.Card.TLabel", background=p["card"],
                    foreground=p["accent"], font=(fam, 10, "bold"))
    style.configure("Title.TLabel", background=p["bg"],
                    foreground=p["text"], font=(fam, 16, "bold"))
    style.configure("Sub.TLabel", background=p["bg"],
                    foreground=p["muted"], font=(fam, 9))
    style.configure("Good.Card.TLabel", background=p["card"],
                    foreground=p["good"], font=(fam, 9, "bold"))
    style.configure("TButton", background=p["card2"], foreground=p["text"],
                    borderwidth=0, focusthickness=0, padding=(10, 5))
    style.map("TButton",
              background=[("pressed", "#141d2a"), ("active", p["line"])],
              foreground=[("disabled", "#5b6c85")])
    style.configure("Accent.TButton", background=p["accent"],
                    foreground="#06131f", padding=(20, 10),
                    font=(fam, 10, "bold"))
    style.map("Accent.TButton",
              background=[("disabled", "#27364c"),
                          ("pressed", p["accent2"]), ("active", "#5cb6ff")],
              foreground=[("disabled", "#5f708a")])
    style.configure("Ghost.TButton", background=p["card"],
                    foreground=p["accent"], padding=(8, 3))
    style.map("Ghost.TButton",
              background=[("active", p["card2"]), ("pressed", p["line"])])
    style.configure("TCheckbutton", background=p["card"], foreground=p["text"],
                    focuscolor=p["card"])
    style.map("TCheckbutton", background=[("active", p["card"])],
              foreground=[("disabled", "#5b6c85")])
    style.configure("TRadiobutton", background=p["card"], foreground=p["text"],
                    focuscolor=p["card"])
    style.map("TRadiobutton", background=[("active", p["card"])],
              foreground=[("disabled", "#5b6c85")])
    style.configure("TCombobox", fieldbackground=p["card2"],
                    background=p["card2"], foreground=p["text"],
                    arrowcolor=p["text"], bordercolor=p["line"],
                    lightcolor=p["card2"], darkcolor=p["card2"])
    style.map("TCombobox", fieldbackground=[("readonly", p["card2"])],
              foreground=[("readonly", p["text"])])
    style.configure("TEntry", fieldbackground=p["card2"], foreground=p["text"],
                    insertcolor=p["text"], bordercolor=p["line"],
                    lightcolor=p["line"], darkcolor=p["line"], padding=4)
    style.configure("TSpinbox", fieldbackground=p["card2"],
                    foreground=p["text"], arrowcolor=p["text"],
                    bordercolor=p["line"], padding=3)
    style.configure("Bar.Horizontal.TProgressbar", troughcolor="#0a0f16",
                    background=p["accent"], bordercolor=p["card"],
                    lightcolor=p["accent"], darkcolor=p["accent"],
                    thickness=14)
    style.configure("Vertical.TScrollbar", background=p["card2"],
                    troughcolor=p["card"], bordercolor=p["card"],
                    arrowcolor=p["muted"], thickness=11)
    style.configure("Horizontal.TScrollbar", background=p["card2"],
                    troughcolor=p["card"], bordercolor=p["card"],
                    arrowcolor=p["muted"], thickness=11)
    for pattern, color in (("background", p["card2"]), ("foreground", p["text"]),
                           ("selectBackground", p["accent"]),
                           ("selectForeground", "#06131f")):
        root.option_add("*TCombobox*Listbox." + pattern, color)
    return style, fam


# ------------------------------------------------------------------ window


class Ui(object):
    """The whole window: files, languages, options, progress and log."""

    def __init__(self, root, files, opts):
        self.root = root
        self.opts = opts
        self.files = []
        self.cancel = threading.Event()
        self.events = queue.Queue()
        self.log = RunLog()
        self.runner = None
        self.done = 0
        self.total = 0
        self.started_at = 0.0
        self.running = False
        self.dnd = False

        p = PALETTE
        root.title(APP)
        root.configure(bg=p["bg"])
        # open in a window that always fits the screen, even on small screens
        screen_w = root.winfo_screenwidth()
        screen_h = root.winfo_screenheight()
        win_w = min(1040, max(720, screen_w - 80))
        win_h = min(746, max(520, screen_h - 110))
        root.geometry("%dx%d+%d+%d" % (win_w, win_h,
                                       max(0, (screen_w - win_w) // 2),
                                       max(0, (screen_h - win_h) // 3)))
        root.minsize(560, 430)
        self.style, self.fam = build_style(root)

        # the very first start of a compact build has to unpack the engine
        splash = None
        if engine_cache_needed():
            root.geometry("470x130")
            splash = tk.Label(root,
                              text="\n  Preparing the OCR engine\n"
                                   "  This happens only on the first start."
                                   "\n",
                              bg=p["card"], fg=p["text"],
                              font=(self.fam, 11), justify="center")
            splash.pack(expand=True, fill="both")
            root.update()

        self.tess, self.tessdata = find_tesseract()
        self.available = set(available_langs(self.tessdata))
        self.psm = int(opts.get("psm") or 3)
        if splash is not None:
            splash.destroy()
            root.geometry("%dx%d+%d+%d" % (win_w, win_h,
                                           max(0, (screen_w - win_w) // 2),
                                           max(0, (screen_h - win_h) // 3)))
            root.update()

        self._build_header()
        body = ttk.Frame(root)
        body.pack(fill="both", expand=True, padx=12, pady=(4, 0))
        body.columnconfigure(0, weight=3, minsize=240)
        body.columnconfigure(1, weight=4, minsize=300)
        body.rowconfigure(0, weight=1, minsize=150)
        self._build_files(body)
        self._build_settings(body)
        self._build_bottom(root)
        self._enable_dnd()
        self._apply_opts()
        self._describe_engine()

        for path in files:
            self.add_path(path)
        self._refresh_counts()

        root.after(120, self.pump)
        if self.opts.get("autostart") and self.files:
            root.after(500, self.start)

    # ------------------------------------------------------------- building

    def _build_header(self):
        p = PALETTE
        head = tk.Frame(self.root, bg=p["bg"])
        head.pack(fill="x", padx=14, pady=(10, 2))
        left = tk.Frame(head, bg=p["bg"])
        left.pack(side="left")
        tk.Label(left, text=APP, bg=p["bg"], fg=p["text"],
                 font=(self.fam, 17, "bold")).pack(anchor="w")
        tk.Label(left, text="Scanned PDFs -> searchable PDF",
                 bg=p["bg"], fg=p["muted"],
                 font=(self.fam, 9)).pack(anchor="w")
        right = tk.Frame(head, bg=p["bg"])
        right.pack(side="right")
        self.engine_label = tk.Label(right, text="", bg=p["bg"], fg=p["good"],
                                     font=(self.fam, 9, "bold"), justify="right")
        self.engine_label.pack(anchor="e")

    def _build_files(self, parent):
        p = PALETTE
        card = tk.Frame(parent, bg=p["card"], highlightthickness=1,
                        highlightbackground=p["line"])
        card.grid(row=0, column=0, sticky="nsew", padx=(0, 8))
        card.columnconfigure(0, weight=1)
        card.rowconfigure(1, weight=1)
        bar = tk.Frame(card, bg=p["card"])
        bar.grid(row=0, column=0, sticky="ew", padx=10, pady=(9, 4))
        tk.Label(bar, text="1.  PDF files", bg=p["card"], fg=p["accent"],
                 font=(self.fam, 10, "bold")).pack(side="left")
        self.count_label = tk.Label(bar, text="", bg=p["card"], fg=p["muted"],
                                    font=(self.fam, 8))
        self.count_label.pack(side="right")
        holder = tk.Frame(card, bg=p["card"])
        holder.grid(row=1, column=0, sticky="nsew", padx=10)
        holder.rowconfigure(0, weight=1)
        holder.columnconfigure(0, weight=1)
        self.listbox = tk.Listbox(holder, bg=p["card2"], fg=p["text"],
                                  selectbackground=p["accent"],
                                  selectforeground="#06131f",
                                  activestyle="none", relief="flat",
                                  highlightthickness=0, font=(self.fam, 9),
                                  height=9, selectmode="extended")
        self.listbox.grid(row=0, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(holder, orient="vertical",
                               command=self.listbox.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.listbox.configure(yscrollcommand=scroll.set)
        self.listbox.bind("<Double-Button-1>", self._open_selected)
        self.listbox.bind("<Delete>", lambda _event: self.remove())
        buttons = tk.Frame(card, bg=p["card"])
        buttons.grid(row=2, column=0, sticky="ew", padx=10, pady=(7, 0))
        ttk.Button(buttons, text="Add PDFs", command=self.add_files).pack(
            side="left")
        ttk.Button(buttons, text="Add folder", command=self.add_folder).pack(
            side="left", padx=4)
        ttk.Button(buttons, text="Remove", command=self.remove).pack(side="left")
        ttk.Button(buttons, text="Clear", command=self.clear).pack(
            side="left", padx=4)
        self.hint = tk.Label(card, text="", bg=p["card"], fg=p["muted"],
                             font=(self.fam, 8), wraplength=360, justify="left")
        self.hint.grid(row=3, column=0, sticky="w", padx=10, pady=(6, 10))

    def _build_settings(self, parent):
        p = PALETTE
        column = tk.Frame(parent, bg=p["bg"])
        column.grid(row=0, column=1, sticky="nsew")
        column.columnconfigure(0, weight=1)
        column.rowconfigure(0, weight=1)
        self._build_languages(column)
        self._build_options(column)

    def _build_languages(self, column):
        p = PALETTE
        card = tk.Frame(column, bg=p["card"], highlightthickness=1,
                        highlightbackground=p["line"])
        card.grid(row=0, column=0, sticky="nsew")
        card.columnconfigure(0, weight=1)
        card.rowconfigure(3, weight=1)
        bar = tk.Frame(card, bg=p["card"])
        bar.grid(row=0, column=0, sticky="ew", padx=10, pady=(9, 2))
        tk.Label(bar, text="2.  Languages", bg=p["card"], fg=p["accent"],
                 font=(self.fam, 10, "bold")).pack(side="left")
        self.lang_label = tk.Label(bar, text="", bg=p["card"], fg=p["muted"],
                                   font=(self.fam, 8))
        self.lang_label.pack(side="right")
        presets = tk.Frame(card, bg=p["card"])
        presets.grid(row=1, column=0, sticky="ew", padx=8)
        tk.Label(presets, text="quick select", bg=p["card"], fg=p["muted"],
                 font=(self.fam, 8)).pack(side="left", padx=(2, 6))
        for name, codes in PRESETS:
            ttk.Button(presets, text=name, style="Ghost.TButton",
                       command=lambda c=codes: self._preset(c)).pack(side="left",
                                                                     padx=1)
        wrap = tk.Frame(card, bg=p["card"])
        wrap.grid(row=3, column=0, sticky="nsew", padx=(10, 6), pady=(4, 6))
        wrap.rowconfigure(0, weight=1)
        wrap.columnconfigure(0, weight=1)
        self.lang_canvas = tk.Canvas(wrap, bg=p["card"], highlightthickness=0,
                                     height=84, bd=0)
        self.lang_canvas.grid(row=0, column=0, sticky="nsew")
        bar2 = ttk.Scrollbar(wrap, orient="vertical",
                             command=self.lang_canvas.yview)
        bar2.grid(row=0, column=1, sticky="ns")
        self.lang_canvas.configure(yscrollcommand=bar2.set)
        inner = tk.Frame(self.lang_canvas, bg=p["card"])
        self.lang_window = self.lang_canvas.create_window((0, 0), window=inner,
                                                          anchor="nw")
        inner.bind("<Configure>", lambda _e: self.lang_canvas.configure(
            scrollregion=self.lang_canvas.bbox("all")))
        self.lang_canvas.bind("<Configure>", lambda e: self.lang_canvas.itemconfigure(
            self.lang_window, width=e.width))
        for seq in ("<MouseWheel>", "<Button-4>", "<Button-5>"):
            self.lang_canvas.bind(seq, self._lang_wheel)
        self.lang_vars = {}
        self.missing_langs = []
        shown = 0
        for name, code in LANGS:
            if self.available and code not in self.available:
                self.missing_langs.append(name)
                continue
            var = tk.BooleanVar(value=(code == "eng"))
            self.lang_vars[code] = var
            row, col = divmod(shown, 3)
            ttk.Checkbutton(inner, text=name, variable=var,
                            command=self._refresh_lang_label).grid(
                row=row, column=col, sticky="w", padx=2, pady=1)
            shown += 1
        for col in range(3):
            inner.columnconfigure(col, weight=1)

    def _build_options(self, column):
        p = PALETTE
        # a scrollable body keeps every option reachable in a small window
        holder = tk.Frame(column, bg=p["bg"])
        holder.grid(row=1, column=0, sticky="ew", pady=(8, 0))
        holder.columnconfigure(0, weight=1)
        canvas = tk.Canvas(holder, bg=p["card"], highlightthickness=0, bd=0,
                           height=300)
        canvas.grid(row=0, column=0, sticky="ew")
        bar = ttk.Scrollbar(holder, orient="vertical", command=canvas.yview)
        bar.grid(row=0, column=1, sticky="ns")
        canvas.configure(yscrollcommand=bar.set)
        opt = tk.Frame(canvas, bg=p["card"])
        canvas.create_window((0, 0), window=opt, anchor="nw", tags="inner")
        opt.bind("<Configure>", lambda _e: canvas.configure(
            scrollregion=canvas.bbox("all")))
        canvas.bind("<Configure>", lambda e: canvas.itemconfigure("inner",
                                                                  width=e.width))
        canvas.bind("<MouseWheel>", lambda e: canvas.yview_scroll(
            -1 if e.delta > 0 else 1, "units"))
        opt.columnconfigure(1, weight=1)
        tk.Label(opt, text="3.  Options", bg=p["card"], fg=p["accent"],
                 font=(self.fam, 10, "bold")).grid(row=0, column=0,
                                                   columnspan=3, sticky="w",
                                                   padx=10, pady=(8, 4))
        tk.Label(opt, text="Quality", bg=p["card"], fg=p["muted"],
                 font=(self.fam, 8)).grid(row=1, column=0, sticky="w", padx=10)
        self.quality = tk.StringVar(value=QUALITIES[0][0])
        ttk.Combobox(opt, textvariable=self.quality, state="readonly",
                     values=[label for label, _v in QUALITIES],
                     width=34).grid(row=1, column=1, columnspan=2, sticky="w",
                                    pady=2)
        tk.Label(opt, text="Save to", bg=p["card"], fg=p["muted"],
                 font=(self.fam, 8)).grid(row=2, column=0, sticky="w", padx=10)
        self.outdir = tk.StringVar()
        ttk.Entry(opt, textvariable=self.outdir).grid(row=2, column=1,
                                                      sticky="ew", pady=2)
        ttk.Button(opt, text="Browse", command=self.browse_out).grid(
            row=2, column=2, padx=(4, 8))
        flags = tk.Frame(opt, bg=p["card"])
        flags.grid(row=3, column=0, columnspan=3, sticky="ew", padx=8,
                   pady=(6, 0))
        self.skip_text = tk.BooleanVar(value=True)
        ttk.Checkbutton(flags, text="Skip pages that already contain text",
                        variable=self.skip_text).pack(anchor="w")
        self.skip_blank = tk.BooleanVar(value=True)
        ttk.Checkbutton(flags, text="Skip blank pages (faster)",
                        variable=self.skip_blank).pack(anchor="w")
        self.crop = tk.BooleanVar(value=True)
        ttk.Checkbutton(flags, text="Trim empty margins (faster)",
                        variable=self.crop).pack(anchor="w")
        self.write_txt = tk.BooleanVar(value=False)
        ttk.Checkbutton(flags, text="Also save the text as .txt",
                        variable=self.write_txt).pack(anchor="w")
        split = tk.Frame(opt, bg=p["card"])
        split.grid(row=4, column=0, columnspan=3, sticky="ew", padx=10,
                   pady=(6, 10))
        tk.Label(split, text="Split output", bg=p["card"], fg=p["muted"],
                 font=(self.fam, 8)).grid(row=0, column=0, columnspan=3,
                                          sticky="w")
        self.split_mode = tk.StringVar(value="none")
        self.split_pages = tk.IntVar(value=50)
        self.split_mb = tk.DoubleVar(value=10)
        ttk.Radiobutton(split, text="Do not split", variable=self.split_mode,
                        value="none").grid(row=1, column=0, columnspan=3,
                                           sticky="w")
        ttk.Radiobutton(split, text="Every", variable=self.split_mode,
                        value="pages").grid(row=2, column=0, sticky="w")
        ttk.Spinbox(split, from_=1, to=100000, textvariable=self.split_pages,
                    width=7).grid(row=2, column=1, sticky="w", padx=4)
        tk.Label(split, text="pages per file", bg=p["card"], fg=p["muted"],
                 font=(self.fam, 8)).grid(row=2, column=2, sticky="w")
        ttk.Radiobutton(split, text="Max", variable=self.split_mode,
                        value="size").grid(row=3, column=0, sticky="w")
        ttk.Spinbox(split, from_=0.5, to=2000, increment=0.5,
                    textvariable=self.split_mb, width=7).grid(row=3, column=1,
                                                              sticky="w", padx=4)
        tk.Label(split, text="MB per file", bg=p["card"], fg=p["muted"],
                 font=(self.fam, 8)).grid(row=3, column=2, sticky="w")

    def _build_bottom(self, root):
        p = PALETTE
        # the buttons sit at the bottom of the window and always stay visible,
        # whatever size the window is dragged to
        buttons = tk.Frame(root, bg=p["bg"])
        buttons.pack(side="bottom", fill="x", padx=12, pady=(6, 10))
        self.start_button = ttk.Button(buttons, text="Start OCR",
                                       style="Accent.TButton", command=self.start)
        self.start_button.pack(side="left")
        self.cancel_button = ttk.Button(buttons, text="Cancel",
                                        command=self.cancel_run,
                                        state="disabled")
        self.cancel_button.pack(side="left", padx=8)
        ttk.Button(buttons, text="Open output folder",
                   command=self.open_folder).pack(side="left")
        ttk.Button(buttons, text="Clear log",
                   command=self.clear_log).pack(side="right")
        statusbar = tk.Frame(root, bg=p["bg"])
        statusbar.pack(side="bottom", fill="x", padx=12, pady=(0, 4))
        self.status = tk.Label(statusbar, text="Ready.", bg=p["bg"],
                               fg=p["text"], font=(self.fam, 9), anchor="w")
        self.status.pack(side="left")
        logbox = tk.Frame(root, bg=p["card"], highlightthickness=1,
                          highlightbackground=p["line"])
        logbox.pack(side="bottom", fill="both", expand=True, padx=12,
                    pady=(2, 0))
        self.logtext = tk.Text(logbox, height=2, bg="#0a0f16", fg=p["muted"],
                               relief="flat", highlightthickness=0,
                               font=("Consolas", 8), wrap="word")
        self.logtext.pack(side="left", fill="both", expand=True, padx=(6, 0),
                          pady=4)
        self.logtext.configure(state="disabled")
        lbar = ttk.Scrollbar(logbox, orient="vertical",
                             command=self.logtext.yview)
        lbar.pack(side="right", fill="y")
        self.logtext.configure(yscrollcommand=lbar.set)

    # ----------------------------------------------------------- small stuff

    def _describe_engine(self):
        # the creator is always shown here, not engine details
        self.engine_label.configure(text=CREATOR, fg=PALETTE["good"])

    def _apply_opts(self):
        opts = self.opts
        if opts.get("langs"):
            wanted = set(opts["langs"])
            for code, var in self.lang_vars.items():
                var.set(code in wanted)
        if opts.get("quality"):
            for label, value in QUALITIES:
                if str(value) == str(opts["quality"]):
                    self.quality.set(label)
        if opts.get("outdir"):
            self.outdir.set(opts["outdir"])
        if opts.get("skip_text") is not None:
            self.skip_text.set(bool(opts["skip_text"]))
        if opts.get("skip_blank") is not None:
            self.skip_blank.set(bool(opts["skip_blank"]))
        if opts.get("write_txt"):
            self.write_txt.set(True)
        if opts.get("split_mode"):
            self.split_mode.set(opts["split_mode"])
            value = opts.get("split_value")
            if value:
                if opts["split_mode"] == "pages":
                    self.split_pages.set(int(value))
                else:
                    self.split_mb.set(float(value))
        self._refresh_lang_label()

    def _preset(self, codes):
        if codes is None:
            codes = list(self.lang_vars)
        wanted = set(codes)
        for code, var in self.lang_vars.items():
            var.set(code in wanted)
        self._refresh_lang_label()

    def selected_langs(self):
        codes = [code for code, var in self.lang_vars.items() if var.get()]
        return codes or (["eng"] if "eng" in self.lang_vars else [])

    def _refresh_lang_label(self):
        chosen = self.selected_langs()
        text = "%d selected" % len(chosen)
        if self.missing_langs:
            text += "  (%d not built in)" % len(self.missing_langs)
        self.lang_label.configure(text=text)

    def _lang_wheel(self, event):
        widget = self.root.winfo_containing(event.x_root, event.y_root)
        while widget is not None:
            if widget is self.lang_canvas:
                break
            widget = getattr(widget, "master", None)
        else:
            return
        if getattr(event, "num", 0) == 4:
            self.lang_canvas.yview_scroll(-2, "units")
        elif getattr(event, "num", 0) == 5:
            self.lang_canvas.yview_scroll(2, "units")
        else:
            self.lang_canvas.yview_scroll(-1 if event.delta > 0 else 1, "units")

    def _refresh_counts(self):
        self.count_label.configure(text="%d file(s)" % len(self.files))
        if self.dnd:
            tip = ("Drag & drop PDF files or folders anywhere in this window.  "
                   "Double click a row to open it.")
        else:
            tip = ("Drag & drop PDF files onto PDF-OCR.exe, use Add PDFs / "
                   "Add folder, or right click a PDF and pick Open with.")
        if self.files:
            tip += "  Select a row and press Remove to drop it."
        self.hint.configure(text=tip)

    def _enable_dnd(self):
        try:
            from tkinterdnd2 import DND_FILES
            for widget in (self.root, self.listbox):
                widget.drop_target_register(DND_FILES)
                widget.dnd_bind("<<Drop>>", self.on_drop)
            self.dnd = True
        except Exception:
            self.dnd = False

    def on_drop(self, event):
        try:
            items = self.root.tk.splitlist(event.data)
        except Exception:
            items = [event.data]
        for item in items:
            self.add_path(item)
        return getattr(event, "action", None)

    # ---------------------------------------------------------------- files

    def add_path(self, path):
        path = os.path.abspath(str(path).strip().strip('"'))
        if os.path.isdir(path):
            added = 0
            for folder, _dirs, names in os.walk(path):
                for name in sorted(names):
                    if name.lower().endswith(".pdf"):
                        if self._append(os.path.join(folder, name)):
                            added += 1
                if added > 400:
                    break
            self._refresh_counts()
            self._log_ui("added %d PDF(s) from %s" % (added, path))
            return
        if not path.lower().endswith(".pdf"):
            self._log_ui("skipped, not a PDF: %s" % path)
            return
        if not os.path.isfile(path):
            self._log_ui("skipped, file not found: %s" % path)
            return
        if self._append(path):
            self._refresh_counts()

    def _append(self, path):
        if path in self.files:
            return False
        self.files.append(path)
        self.listbox.insert("end", path)
        return True

    def add_files(self):
        chosen = filedialog.askopenfilenames(
            title="Choose PDF files",
            filetypes=[("PDF files", "*.pdf"), ("All files", "*.*")])
        for path in chosen:
            self.add_path(path)

    def add_folder(self):
        folder = filedialog.askdirectory(title="Choose a folder that holds PDFs")
        if folder:
            self.add_path(folder)

    def remove(self):
        if self.running:
            return
        for index in reversed(self.listbox.curselection()):
            self.listbox.delete(index)
            del self.files[index]
        self._refresh_counts()

    def clear(self):
        if self.running:
            return
        self.files = []
        self.listbox.delete(0, "end")
        self._refresh_counts()

    def _open_selected(self, _event=None):
        for index in self.listbox.curselection():
            try:
                os.startfile(self.files[index])
            except Exception as exc:
                self._log_ui("could not open the file: %s" % exc)

    def browse_out(self):
        folder = filedialog.askdirectory(title="Where should the OCR PDFs go?")
        if folder:
            self.outdir.set(folder)

    def open_folder(self):
        target = self.outdir.get().strip()
        if not target and self.files:
            target = os.path.dirname(self.files[0])
        if target and os.path.isdir(target):
            try:
                os.startfile(target)
                return
            except Exception as exc:
                self._log_ui("could not open the folder: %s" % exc)
                return
        messagebox.showinfo(APP, "There is no output folder yet.")

    def clear_log(self):
        self.logtext.configure(state="normal")
        self.logtext.delete("1.0", "end")
        self.logtext.configure(state="disabled")

    def _log_ui(self, message, record=True):
        line = self.log.add(message) if record else "[%s] %s" % (
            time.strftime("%H:%M:%S"), message)
        self.logtext.configure(state="normal")
        self.logtext.insert("end", line + "\n")
        self.logtext.see("end")
        self.logtext.configure(state="disabled")
        return line

    # ------------------------------------------------------------- the run

    def start(self):
        if self.running:
            return
        if not self.files:
            messagebox.showwarning(APP, "Add at least one PDF file first.")
            return
        if not self.tess:
            messagebox.showerror(
                APP, "The Tesseract OCR engine was not found.\n\n"
                     "PDF-OCR.exe must stay next to its 'tesseract' folder.")
            return
        langs = self.selected_langs()
        if not langs:
            messagebox.showwarning(APP, "Please select at least one language.")
            return
        cfg = self._collect()
        self.cancel.clear()
        self.done = 0
        self.total = 0
        self.started_at = time.time()
        self.running = True
        self.start_button.configure(state="disabled")
        self.cancel_button.configure(state="normal")
        self.status.configure(text="Working ...")
        self._log_ui("start  %s  (%d file(s))" % (cfg.describe(), len(self.files)))
        threading.Thread(target=self._work, args=(cfg,), daemon=True).start()

    def _collect(self):
        cfg = Settings()
        cfg.langs = "+".join(self.selected_langs())
        label = self.quality.get()
        cfg.quality = next((value for text, value in QUALITIES if text == label),
                           "auto")
        cfg.skip_text = bool(self.skip_text.get())
        cfg.skip_blank = bool(self.skip_blank.get())
        cfg.crop = bool(self.crop.get())
        cfg.write_txt = bool(self.write_txt.get())
        cfg.outdir = self.outdir.get().strip()
        cfg.split_mode = self.split_mode.get()
        cfg.psm = self.psm
        if cfg.split_mode == "pages":
            cfg.split_value = int(self.split_pages.get() or 50)
        elif cfg.split_mode == "size":
            cfg.split_value = float(self.split_mb.get() or 10.0)
        else:
            cfg.split_value = 0
        return cfg

    def _progress(self, count):
        self.events.put(("pages", count))

    def _work(self, cfg):
        outs = []
        errors = []
        stats = {"pages": 0, "ocr": 0, "text": 0, "blank": 0, "failed": 0}
        runner = TessRunner(self.tess, self.tessdata, self.log, self.psm)
        self.runner = runner
        log = UiLog(self.log, self.events)
        try:
            for path in list(self.files):
                try:
                    with pymupdf.open(path) as doc:
                        self.events.put(("total", doc.page_count))
                except Exception as exc:
                    errors.append("%s: %s" % (os.path.basename(path), exc))
            for index, path in enumerate(list(self.files), 1):
                if self.cancel.is_set():
                    break
                self.events.put(("status", "File %d of %d:  %s"
                                 % (index, len(self.files),
                                    os.path.basename(path))))
                log.add("file %d/%d  %s" % (index, len(self.files),
                                            os.path.basename(path)))
                try:
                    files, one = process_file(path, cfg, self.cancel, runner,
                                              log, self._progress)
                except Exception as exc:
                    errors.append("%s: %s" % (os.path.basename(path), exc))
                    log.add("FAILED %s: %s" % (os.path.basename(path), exc))
                    log.add(traceback.format_exc(limit=3))
                    continue
                if files:
                    outs.extend(files)
                    self.events.put(("out", list(files)))
                for key in stats:
                    stats[key] += one.get(key, 0)
        except Exception as exc:                     # last resort
            errors.append("unexpected error: %s" % exc)
            log.add(traceback.format_exc(limit=5))
        finally:
            self.runner = None
            self.events.put(("done", (outs, errors, stats)))

    def cancel_run(self):
        self.cancel.set()
        self.status.configure(text="Cancelling ...")
        self._log_ui("cancel requested")
        if self.runner is not None:
            self.runner.kill_all()

    def pump(self):
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "log":
                    self.logtext.configure(state="normal")
                    self.logtext.insert("end", payload + "\n")
                    self.logtext.see("end")
                    self.logtext.configure(state="disabled")
                elif kind == "pages":
                    self.done += payload
                    self.status.configure(text="%d pages done" % self.done)
                elif kind == "total":
                    self.total += payload
                elif kind == "status":
                    self.status.configure(text=payload)
                elif kind == "done":
                    self._finish(payload)
        except queue.Empty:
            pass
        self.root.after(120, self.pump)

    def _rate_text(self):
        """Short status: how many pages are done."""
        return "%d pages done" % self.done

    def _finish(self, payload):
        outs, errors, stats = payload
        self.running = False
        self.start_button.configure(state="normal")
        self.cancel_button.configure(state="disabled")
        self._write_run_log(outs)
        summary = "%d page(s) OCR'd, %d already had text, %d blank" % (
            stats.get("ocr", 0), stats.get("text", 0), stats.get("blank", 0))
        if stats.get("failed"):
            summary += ", %d failed" % stats["failed"]
        self._log_ui("summary: " + summary)
        if self.cancel.is_set():
            self.status.configure(text="Cancelled - " + summary)
            return
        self.status.configure(text="Finished - " + summary)
        if errors:
            messagebox.showerror(APP, "These files could not be processed:\n\n"
                                 + "\n".join(errors[:8]))
            return
        if outs:
            folder = os.path.dirname(outs[0])
            if messagebox.askyesno(APP, "%d file(s) created in:\n%s\n\nOpen that "
                                        "folder now?" % (len(outs), folder)):
                try:
                    os.startfile(folder)
                except Exception as exc:
                    self._log_ui("could not open the folder: %s" % exc)

    def _write_run_log(self, outs):
        if not outs:
            return
        try:
            path = os.path.join(os.path.dirname(outs[0]), "PDF-OCR-log.txt")
            with open(path, "a", encoding="utf-8", errors="replace") as handle:
                handle.write("\n===== %s %s   %s =====\n"
                             % (APP, VERSION, time.strftime("%Y-%m-%d %H:%M:%S")))
                handle.write("created: %s\n"
                             % ", ".join(os.path.basename(p) for p in outs))
                handle.write(self.log.text() + "\n")
        except Exception:
            pass

    def show_help(self):
        """Kept for compatibility; the help button no longer exists."""
        return


class UiLog(object):
    """RunLog wrapper that also pushes each line to the window."""

    def __init__(self, log, events):
        self.log = log
        self.events = events

    def add(self, message):
        line = self.log.add(message)
        self.events.put(("log", line))
        return line


HELP_TEXT = """How to use PDF OCR

1.  Add the scanned PDFs - drag & drop them onto this window (or onto
    PDF-OCR.exe), or use "Add PDFs" / "Add folder".
2.  Pick the languages that appear on the pages (English is preselected).
3.  Press "Start OCR". A new file <name>_ocr.pdf appears next to the
    original - same look, but every page is now real, selectable text.
"""


def make_root():
    """Use tkinterdnd2 when it is available so files can be dropped in."""
    try:
        from tkinterdnd2 import TkinterDnD
        return TkinterDnD.Tk()
    except Exception:
        return tk.Tk()


def parse_args(argv):
    opts = {"autostart": True}
    files = []
    index = 0
    while index < len(argv):
        arg = argv[index]
        low = arg.lower()
        if low in ("--help", "-h", "/?", "help"):
            opts["help"] = True
        elif low == "--selftest":
            opts["selftest"] = True
        elif low == "--no-autostart":
            opts["autostart"] = False
        elif low == "--collect-engine" and index + 2 < len(argv):
            opts["collect_engine"] = [argv[index + 1], argv[index + 2]]
            index += 2
        elif low == "--pack-engine" and index + 2 < len(argv):
            opts["pack_engine"] = [argv[index + 1], argv[index + 2]]
            index += 2
        elif low in ("--out", "--outdir", "-o") and index + 1 < len(argv):
            index += 1
            opts["outdir"] = argv[index]
        elif low == "--langs" and index + 1 < len(argv):
            index += 1
            opts["langs"] = [code.strip() for code in argv[index].split("+")
                             if code.strip()]
        elif low == "--quality" and index + 1 < len(argv):
            index += 1
            opts["quality"] = argv[index]
        elif low == "--psm" and index + 1 < len(argv):
            index += 1
            opts["psm"] = argv[index]
        elif low == "--split" and index + 1 < len(argv):
            index += 1
            mode, _, rest = argv[index].partition(":")
            opts["split_mode"] = mode or "none"
            if rest:
                opts["split_value"] = rest
        elif low == "--txt":
            opts["write_txt"] = True
        elif low == "--no-skip-text":
            opts["skip_text"] = False
        elif low == "--keep-blank":
            opts["skip_blank"] = False
        elif arg[:1] != "-":
            files.append(arg)
        index += 1
    return files, opts


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    files, opts = parse_args(argv)
    if opts.get("selftest"):
        lines, good = selftest()
        path = write_report(lines)
        safe_out("\n".join(lines))
        safe_out("report written to %s" % path)
        return 0 if good else 1
    if opts.get("collect_engine"):
        src, dst = opts["collect_engine"]
        log = RunLog()
        code = collect_engine(src, dst, log)
        safe_out(log.text())
        return code
    if opts.get("pack_engine"):
        src, dst = opts["pack_engine"]
        log = RunLog()
        code = pack_engine(src, dst, log)
        safe_out(log.text())
        return code
    if opts.get("help"):
        # the help window was removed; the program simply opens
        opts.pop("help", None)
    root = make_root()
    Ui(root, files, opts)
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
