# pgadmin > set server properties to use user geotabuser > click on db under server > enter vircom43 as password

# dotnet CheckmateServer.dll CreateDatabase postgres companyName=geotabdemo administratorUser=<your email address> administratorPassword=<choose a password> sqluser=geotabuser sqlpassword=vircom43

# Nav to MyGeotab/Checkmate/bin/Debug/netcoreapp3.1
cd repos/MyGeotab/Checkmate/bin/Debug/netcoreapp3.1/

dotnet CheckmateServer.dll CreateDatabase postgres companyName=geotabdemo administratorUser=dawsonmyers@geotab.com administratorPassword=password sqluser=geotabuser sqlpassword=vircom43