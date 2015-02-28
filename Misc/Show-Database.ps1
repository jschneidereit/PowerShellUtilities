param (
    [string]$Server = ".",
    [string]$DBName = "Name",
    [string]$Table = "TName"
)

$ConnectionString = "Server = $Server; Database = $DBName; Integrated Security = True"
$Query = "SELECT * from $Table"

$Connection = New-Object System.Data.SqlClient.SqlConnection
$Connection.ConnectionString = $ConnectionString

$DataSet = New-Object System.Data.DataSet
$Command = New-Object System.Data.SqlClient.SqlCommand
$Adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$Command.CommandText = $Query
$Command.Connection = $Connection
$Adapter.SelectCommand = $Command
$Adapter.Fill($DataSet)
$DataSet.Tables