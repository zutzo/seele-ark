'检查脚本是否以提升的权限运行。
'如果没有，则使用“runas”动词重新启动自己以获得提升权限。
If WScript.Arguments.Named.Exists("elevated") = False Then
    On Error Resume Next '启用错误处理，以处理ShellExecute潜在的错误
    '创建Shell对象
    Set objShell = CreateObject("Shell.Application")
    If objShell Is Nothing Then
        MsgBox "无法创建Shell对象。无法提升权限。", vbCritical, "错误"
        WScript.Quit
    End If

    '尝试以管理员权限重新启动脚本
    '参数：文件，参数，工作目录，动词，窗口显示状态
    '“runas”动词触发提升。窗口状态1（SW_SHOWNORMAL）对于UAC是必要的。
    objShell.ShellExecute "wscript.exe", """" & WScript.ScriptFullName & """ /elevated", "", "runas", 1
    
    If Err.Number <> 0 Then
        '处理潜在的错误，例如用户取消UAC提示
        If Err.Number = 1223 Or Err.Number = 5 Then ' 1223: ERROR_CANCELLED（UAC拒绝），5: 访问被拒绝（通常是UAC拒绝/策略）
             '这里不需要消息，用户主动取消。
        Else
            MsgBox "提升脚本失败。错误: " & Err.Number & " - " & Err.Description, vbCritical, "提升错误"
        End If
    End If
    Err.Clear '清除错误
    On Error GoTo 0 '禁用错误处理
    Set objShell = Nothing
    WScript.Quit '退出原始的未提升实例
Else
    ' ----- 本部分仅在脚本已成功以提升权限重新启动时运行 -----
    On Error GoTo 0 '确保默认错误处理处于活动状态

    Set WS = CreateObject("WScript.Shell")
    Set FSO = CreateObject("Scripting.FileSystemObject")

    '获取脚本所在的目录
    Dim scriptDir
    scriptDir = FSO.GetParentFolderName(WScript.ScriptFullName)

    '构造命令以更改目录并运行mihomo.exe
    '输出和错误重定向到脚本目录下的run.logs
    Dim command
    command = "cmd /c cd /d """ & scriptDir & """ & mihomo.exe -d . > run.logs 2>&1" 

    '以隐藏方式（0）运行命令，并等待其完成（True）
    Dim exitCode
    exitCode = WS.Run(command, 0, True) 

    '清理对象
    Set WS = Nothing
    Set FSO = Nothing
    '提升的脚本实例将在完成后自动退出
End If