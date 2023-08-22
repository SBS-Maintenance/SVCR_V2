text := ""
Loop, 10
{
Random, rand, 1, 2000
text .= rand . "`r`n"
}

MsgBox %text%