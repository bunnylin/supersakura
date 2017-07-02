@echo off
REM This compiles the engine and tools, and puts everything in a zip file.
REM Remember to update releasefiles.txt to add new files to the release.

call comp -n -B supersakura-con
if NOT %ERRORLEVEL%==0 exit /b
call comp -n -B decomp
if NOT %ERRORLEVEL%==0 exit /b
call comp -n recomp
if NOT %ERRORLEVEL%==0 exit /b
call comp -f supersakura
if NOT %ERRORLEVEL%==0 exit /b

call recomp supersakura
if NOT %ERRORLEVEL%==0 exit /b

7z a -mx9 sakubin.zip @releasefiles.txt
move /Y sakubin.zip \website\ssakura\
