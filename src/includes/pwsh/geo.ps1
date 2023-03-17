#!/
function Geo() {
    Write-Output  'hi'
    Write-Output  "hi"
    Write-Output $input
    Write-Output @args
    Write-Output args@ArgumentList
    _geo @ArgumentList
}
function _Geo() {
    Write-Output "_geo=" $1 $2 $3
    Write-Output "@($Args)"
    Write-Output "@($ArgumentList)"
    Write-Output "@($input)"
}
geo "hhh" 1 2 3
