
Function AWS-BuildEnv($FilePath){
#This script needs an AWS Account configured, a keypair configured in the region you plan to run this on.
$newenv = get-content $FilePath -raw | convertfrom-json
#$newenv = get-content "C:\Users\sthayne\Documents\Powershell Scripts\AWS\Ansible\AnsibleEnvironmentjson.txt" -raw | convertfrom-json



ForEach ($VPC in $newenv.VPCS)
    {

    $region = $VPC.Region

    $NEWVPC = New-EC2Vpc -CidrBlock $VPC.CIDR -Region $region
    Write-Host "Creating VPC: CIDR: " $VPC.CIDR " In $region"
    Do{Start-sleep 5}
    Until((Get-EC2Vpc -VpcId $NEWVPC.VpcId -Region $region).State -eq "available")
    $Tag = New-Object Amazon.EC2.Model.Tag("Name",$VPC.Name)
    New-EC2Tag -Resource $NEWVPC.VpcId -Tag $Tag -Region $region
    Write-Host "VPC Created"

    #IGateway tag failed
    If ($VPC.IGateway -eq "True")
        {
        Write-Host "Creating Internet Gateway in VPC: "$VPC.Name
        $NEWIGW = New-EC2InternetGateway -Region $region
        Add-EC2InternetGateway -InternetGatewayId $NEWIGW.InternetGatewayId -VpcId $NEWVPC.VpcId -Region $region
        $Tag = New-Object Amazon.EC2.Model.Tag("Name",("IGW-"+($VPC.Name)))
        New-EC2Tag -resource $NEWIGW.InternetGatewayId -tag $Tag -Region $region
        }


    ForEach ($SG in $VPC.SecurityGroups)
        {
        Write-Host "Creating new Security Group"
        $NEWSG = New-EC2SecurityGroup -GroupName ($SG.Name) -VpcId $NEWVPC.vpcid -Region $region -Description ($SG.Description)
        
        ForEach ($RL in $SG.Rules)
            {
            $rule = new-object Amazon.EC2.Model.IpPermission
            $rule.iprange = $RL.IPRange
            $rule.FromPort = $RL.FromPort
            $rule.ToPort = $RL.ToPort
            $rule.IpProtocol = $RL.Protocol

            Grant-EC2SecurityGroupIngress -GroupId $NEWSG -IpPermission $rule -region $region

            $rule = $null
            }

        $NEWSG = $null
        }


    ForEach ($Subnet in $VPC.SUBNETS)
        {
        $NEWSUBNET = New-EC2Subnet -region $region -VpcId $NEWVPC.VpcId -CidrBlock $subnet.CIDR 
        Write-Host "Creating Subnet: " $NEWSUBNET.CidrBlock
        Do{Start-sleep 5}
        Until((Get-EC2Subnet -SubnetId $NEWSUBNET.SubnetId -Region $region).state -eq "available")

        $Tag = New-Object Amazon.EC2.Model.Tag("Name",$subnet.Name)
        New-EC2Tag -Resource $NEWSUBNET.SubnetId -tag $Tag -Region $region
        $Tag = $null


        ForEach ($Instance in $Subnet.Instances)
            {
            #Build command
            $NICommand = New-Object System.Text.StringBuilder("New-EC2Instance")
            $params = (Get-Help New-EC2Instance -Parameter * | Sort-Object position)
            ForEach ($prm in $params)
                {
                If (($Instance.($prm.name) -ne $null) -and ($prm.name -ne "SecurityGroup")) 
                    {
                    If (((($Instance.($prm.name).GetType()).Name) -eq "String") -and (($Instance.($prm.name)).contains(" ")))
                        {
                        $result = $NICommand.append(" -"+($prm.name) +" "+ '"' + $instance.($prm.name) + '"')
                        }
                    Else
                        {
                        $result = $NICommand.append(" -"+($prm.name) +" "+ $instance.($prm.name))
                        }
                    
                    }
                }
                If (($Instance.SecurityGroup -ne "") -and ($Instance.SecurityGroup -ne $null)) {$result = $NiCommand.append(" -SecurityGroupId " + (Get-EC2SecurityGroup -Region $region | Where-Object {($_.vpcid -eq $NEWVPC.vpcid) -and ($_.groupname -eq $Instance.SecurityGroup)}).GroupId + " ")}
                $result = $NICommand.append(" -SubnetId " + $NEWSUBNET.SubnetId + " ")
                $result = $NICommand.append(" -Region " + $region + " ")


            Write-Host "Creating EC2 Instance: "$Instance.Name
            $NEWInstance = Invoke-Expression -command $NICommand.Tostring()
            #$NEWInstance = New-EC2Instance -ImageId $Instance.ImageId -InstanceType $Instance.InstanceType -SubnetId $NEWSUBNET.SubnetId -MinCount $Instance.NumberOf -MaxCount $Instance.NumberOf -Region $region -UserDataFile $Instance.UserDataFile -EncodeUserData -AssociatePublicIp $Instance.AssociatePublicIp -KeyName $Instance.KeyName -SecurityGroupId (Get-EC2SecurityGroup -Region $region | Where-Object {($_.vpcid -eq $NEWVPC.vpcid) -and ($_.groupname -eq $Instance.SecurityGroup)}).GroupId
            DO{Start-Sleep 5}
            Until (((Get-EC2InstanceStatus -InstanceId ($NEWInstance.runninginstance).InstanceId -Region $region).InstanceState.Name -eq "running"))

            ForEach($itag in $Instance.Tags)
                {
                ForEach ($tg in ($Instance.Tags | Get-Member -MemberType Properties))
                    {
                    $Tag = New-Object Amazon.EC2.Model.Tag($tg.Name, $itag.($tg.Name))
                    New-EC2Tag -resource ($NEWInstance.runninginstance).InstanceId -tag $Tag -Region $region
                    $Tag = $null
                    }
                }

            Write-Host "EC2 Instance Created"
            If ($Instance.AssociatePublicIp -eq 1)
                {
                Write-Host "Public IP is: "(Get-EC2Instance -Region $region $NEWInstance).RunningInstance.PublicIPAddress
                }

            $NEWInstance = $null
            }
  
               
        ForEach ($RT in $Subnet.RTables)
            {
            Write-Host "Creating New Route table and routes"
            $NEWROUTETABLE = New-EC2RouteTable -VpcId $NEWVPC.VpcId -Region $region
            $Tag = New-Object Amazon.EC2.Model.Tag("Name", $RT.Name)
            New-EC2Tag -resource $NEWROUTETABLE.RouteTableId -tag $Tag -Region $region
            $Tag = $null

            ForEach($Route in $RT.Routes)
                {
                If ($Route.Target -eq "IGateway") 
                {
                $Route.Target = $NEWIGW.InternetGatewayId
                $NEWROUTE = New-EC2Route -RouteTableId $NEWROUTETABLE.RouteTableId -Region $region -GatewayId $Route.Target -DestinationCidrBlock $Route.DestinationCIDR
                }
                Else
                {
                $NEWROUTE = New-EC2Route -RouteTableId $NEWROUTETABLE.RouteTableId -Region $region -InstanceId (Get-EC2Instance -Region $region | Where-Object {$_.Instances[0].Tags[0].Value -eq ($route.Target)})$Route.Target -DestinationCidrBlock $Route.DestinationCIDR
                }
                Register-EC2RouteTable -RouteTableId $NEWROUTETABLE.RouteTableId -SubnetId $NEWSUBNET.SubnetId -Region $region

                $NEWROUTE = $null
                }

            $NEWROUTETABLE = $null
            }
        
        $NEWSUBNET = $null
        }
    
    $NEWVPC = $null
    $NEWIGW = $null
    $region = $null
    }
    }
