Function Shutdown-AWSInstances(){
$outstring = new-object System.Text.StringBuilder

$result = Get-AWSRegion us-east-2
     $result = $outstring.AppendLine()
     $result = $outstring.AppendLine()
     $result = $outstring.AppendLine("Searching for running instances and stopping them")
     $result = $outstring.AppendLine("___________________________________")
ForEach ($Region in (Get-AWSRegion))
    {
    $result = $outstring.AppendLine()
    $result = $outstring.AppendLine("**"+($Region.Region))
    ForEach ($Instance in (Get-EC2Instance -Region $Region))
        {
            if ($Instance.instances[0].state.Code -eq 16)
            {
            $result = $outstring.AppendLine("Stopping"+($Instance.Instances[0].InstanceId)+"With a state of:"+($Instance.instances[0].state.Name))
            $result = Stop-EC2Instance -Region $Region.Region -InstanceId $Instance.Instances[0].InstanceId
            }
        }
     }
     $result = $outstring.AppendLine()
     $result = $outstring.AppendLine()
     $result = $outstring.AppendLine("STATUS of all instances")
     $result = $outstring.AppendLine("___________________________________")

ForEach ($Region in (Get-AWSRegion))
    {
     $result = $outstring.AppendLine()
          $result = $outstring.AppendLine("**"+($Region.Region))

    ForEach ($Instance in (Get-EC2Instance -Region $Region))
        {
            $result = $outstring.AppendLine(($Instance.Instances[0].InstanceId)+"With a state of:"+($Instance.instances[0].state.Name))
        }
     }



     Return $outstring.ToString()

     }
     