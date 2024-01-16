#region Setup########################################################################
# Prompt the user for API Key
cls
if($apikey -eq $null){
    $apikey=Read-Host -Prompt "Paste your API key for Freshservice"}
else{
    $samesession=Read-host "It looks like you are running this again based on a previous session. Would you like to change the tenant or API Key? Type yes and hit enter if so, otherwise script will use existing values."
    if($samesession -eq 'Yes'){
        cls
        $apikey=Read-Host -Prompt "Paste your API key for Freshservice"
        $tenant=Read-Host -Prompt "Provide the domain prefix target. Ex: companyname"
        if ($tenant -match '\.') {
            Write-host "Enter only the string of characters after https:// and the first period. You will be prompted again in 5 seconds."
            start-sleep 5
            $tenant=$null
            cls
            }
        else{}
    }
    }
    else{}

#Convert API to base64
$user=$apikey+":"
$pwd=[Convert]::ToBase64String([char[]]$user)
#Get tenant ID from user
if($tenant -eq $null){
        $tenant=Read-Host -Prompt "Provide the domain prefix target. Ex: companyname"
            if ($tenant -match '\.') {
                Write-host "Enter only the string of characters after https:// and the first period. You will be prompted again in 5 seconds."
                start-sleep 5
                $tenant=$null
                cls
            }
            else{}
}

#Check if tenant is sandbox and warn if not
if($tenant -notmatch "sandbox"){
    Write-warning "You have not specified a sandbox instance to run this script against. Use Control+C to abort the script if this is not the intent."
    $proceed=Read-host "Type continue to proceed with the script actions"
    if($proceed -eq "continue"){
    }
    else{
    cls
    Write-host "Challenge phrase failed. Exiting."
    break}
    }

#Build API headers
$url="https://$tenant.freshservice.com/api/v2/asset_types?per_page=200"
$headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Basic $pwd"}

#Get list of asset types and confirm. If call failed, exits script.
$list=Invoke-WebRequest -Headers $headers -Method Get -uri $url
if($list.StatusCode -eq 200){
    Write-Host "API key validated. Please select an option from the next screen."
    Start-sleep 2
}
else{
    Read-Host "API key provided not valid. Press any key to exit and try again."
    exit
}
$parsedlist=$list.Content|ConvertFrom-Json
$alllist=$parsedlist.asset_types|Where-Object {$_.visible -eq 'True'}|select id, name|Sort-Object -Property name

# Display menu to select asset type in scope
cls
Write-Host "Select an option:"
for ($i = 0; $i -lt $alllist.Count; $i++) {
    Write-Host "$($i + 1). $($alllist.name[$i])"
}

# Get and process desired asset
$choice = Read-Host "Enter the number (1-$($alllist.Count))"
if ($choice -ge 1 -and $choice -le $alllist.Count) {
    $selectedItem = $alllist[$choice - 1]
    $selecteditemid=$selectedItem.id
    Write-Output "You selected: $($selectedItem.name)"
    Start-Sleep -Seconds 3
}  else {
    Write-Output "Invalid selection. Please enter a number between 1 and $($alllist.Count) or Ctrl+C to quit."
    Start-Sleep -Seconds 2
}
#endregion###########################################################################

#Display a final warning to the user
if($scope -ne 0 -and $tenant -notmatch "sandbox"){
    cls
    Write-warning "You are about to trigger a deletion of $scope $($selecteditem.name)'s from a non-sandbox environment. This is the last chance to bail out."
    $confirm=Read-host -Foregroundcolor Red "Please confirm you want to proceed by entering confirmed, else use Ctl+C or type quit to exit"
    if($confirm -eq 'confirmed'){
    Write-host "Confirmation received, 5 seconds to start. Dont say you werent warned!" -ForegroundColor Red
    start-sleep 5}
    else{}}


#region Get list of devices
cls
$list="https://$tenant.freshservice.com/api/v2/assets?filter=`"asset_type_id:$($selecteditem.id)`""
$assets=Invoke-WebRequest -Uri $list -Method get -Headers $headers -ErrorAction Stop
$scope=$assets.Headers["X-Search-Results-Count"]
$json=$assets.Content|ConvertFrom-Json
$ids=$json.assets|ForEach-Object {$_.display_id}

Write-host "Mass deletion event triggered for $($selecteditem.name). The total devices found is $scope. An update will be provided each time a new set of 30 assets is pulled and deleted."
$ids=1
$total=0
#endregion############################################################################

#region Permanently delete all devices################################################
$assets=Invoke-WebRequest -Uri $list -Method get -Headers $headers -ErrorAction Stop
$scope=$assets.Headers["X-Search-Results-Count"]
$json=$assets.Content|ConvertFrom-Json
$ids=$json.assets|ForEach-Object {$_.display_id}

if($scope -ne 0){
    do{
    write-host $ids.count"were found. So anyways, I started blasting!"
        foreach($asset in $ids){
                $apiUrl = "https://$tenant.freshservice.com/api/v2/assets/$asset/delete_forever"
                try{
                    $response=Invoke-WebRequest -Uri $apiUrl -Method put -Headers $headers -ErrorAction Stop
                    $total++ 
                    if ($response.Headers["X-Ratelimit-Remaining"] -eq 0) {
                        cls
                        Write-warning "Out of ammo! Reloading API requests! This takes 60 seconds!"
                        Start-sleep 55
                        Write-warning "Locked and loaded! Let's get back to it!"
                        start-sleep 5
                        }
                    }
                catch{
                    Write-Host "Could not delete asset number $asset." $_} 
        }
        Write-host "Deleted $total so far. Here we go again!"
    $assets=Invoke-WebRequest -Uri $list -Method get -Headers $headers -ErrorAction Stop
    $scope=$assets.Headers["X-Search-Results-Count"]
    $json=$assets.Content|ConvertFrom-Json
    $ids=$json.assets|ForEach-Object {$_.display_id}
    }
    while($scope -ne 0)
    }
else{
Write-host "No devices of" $selecteditem.name"type found. Exiting."
break
}

Write-host "Script completed. Removed" $total $($selecteditem.name)"'s of an expected $scope. You have" $response.Headers["X-Ratelimit-Remaining"] "api interactions left this minute."
$total=0
#endregion############################################################################