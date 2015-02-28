param (
    [string]$Server = ".",
    [string]$DBName = "DataBaseName",
    [string]$Table = "TableName",
    [int]$Count = 5
)

$ConnectionString = "Server = $Server; Database = $DBName; Integrated Security = True"
$Query = "SELECT * from $Table"

$Connection = New-Object System.Data.SqlClient.SqlConnection
$DataSet = New-Object System.Data.DataSet
$Command = New-Object System.Data.SqlClient.SqlCommand
$Adapter = New-Object System.Data.SqlClient.SqlDataAdapter

$Connection.ConnectionString = $ConnectionString
$Command.CommandText = $Query
$Command.Connection = $Connection
$Adapter.SelectCommand = $Command
$Adapter.Fill($DataSet)

$length = $DataSet.Tables[0].Rows.Count

if ($length -gt 10)
{
    $DataSet.Tables[0].Rows | Select-Object -First $Count
}
else
{
    $DataSet.Tables[0].Rows
}