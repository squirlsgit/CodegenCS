[cmdletbinding()]
param(
    [Parameter(Mandatory=$False)]
    [ValidateSet('Release','Debug')]
    [string]$configuration="Release"
)

# How to run: .\build.ps1   or   .\build.ps1 -configuration Debug


$msbuild = ( 
    "$Env:programfiles (x86)\Microsoft Visual Studio\2017\BuildTools\MSBuild\15.0\Bin\msbuild.exe",
    "$Env:programfiles (x86)\Microsoft Visual Studio\2017\Enterprise\MSBuild\15.0\Bin\msbuild.exe",
    "$Env:programfiles (x86)\Microsoft Visual Studio\2017\Professional\MSBuild\15.0\Bin\msbuild.exe",
    "$Env:programfiles (x86)\Microsoft Visual Studio\2019\Professional\MSBuild\Current\Bin\msbuild.exe",
          "$Env:programfiles\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\msbuild.exe",
    "$Env:programfiles (x86)\Microsoft Visual Studio\2017\Community\MSBuild\15.0\Bin\msbuild.exe",
    "${Env:ProgramFiles(x86)}\MSBuild\14.0\Bin\MSBuild.exe",
    "${Env:ProgramFiles(x86)}\MSBuild\12.0\Bin\MSBuild.exe"
) | Where-Object { Test-Path $_ } | Select-Object -first 1

Remove-Item -Recurse -Force -ErrorAction Ignore ".\packages-local"
Remove-Item -Recurse -Force -ErrorAction Ignore "$env:HOMEDRIVE$env:HOMEPATH\.nuget\packages\codegencs"
Remove-Item -Recurse -Force -ErrorAction Ignore "$env:HOMEDRIVE$env:HOMEPATH\.nuget\packages\codegencs.dbschema"

New-Item -ItemType Directory -Force -Path ".\packages-local"

dotnet clean 
if ($error) {
    # when target frameworks are added/modified dotnet clean might fail and we may need to cleanup the old dependency tree
    Get-ChildItem $Path -Recurse | Where{$_.FullName -Match ".*\\obj\\.*project.assets.json$"} | Remove-Item
    dotnet clean 
}

# CodegenCS + nupkg/snupkg
& $msbuild ".\CodegenCS\CodegenCS.csproj"                          `
           /t:Restore /t:Build /t:Pack                             `
           /p:PackageOutputPath="..\packages-local\"               `
           '/p:targetFrameworks="netstandard2.0;net472;net5.0"'    `
           /p:Configuration=$configuration                         `
           /p:IncludeSymbols=true                                  `
           /p:SymbolPackageFormat=snupkg                           `
           /verbosity:minimal                                      `
           /p:ContinuousIntegrationBuild=true


# CodegenCS.DbSchema + nupkg/snupkg
& $msbuild ".\CodegenCS.DbSchema\CodegenCS.DbSchema.csproj"        `
           /t:Restore /t:Build /t:Pack                             `
           /p:PackageOutputPath="..\packages-local\"               `
           '/p:targetFrameworks="netstandard2.0;net472;net5.0"'    `
           /p:Configuration=$configuration                         `
           /p:IncludeSymbols=true                                  `
           /p:SymbolPackageFormat=snupkg                           `
           /verbosity:minimal                                      `
           /p:ContinuousIntegrationBuild=true



if ($configuration -eq "Release")
{
    # Can clean again since dotnet-codegencs will use Nuget references
    dotnet clean
    Remove-Item -Recurse -Force -ErrorAction Ignore  .\dotnet-codegencs\bin\
    Remove-Item -Recurse -Force -ErrorAction Ignore  .\dotnet-codegencs\obj\
    Remove-Item -Recurse -Force -ErrorAction Ignore  .\CodegenCS.DbSchema.Extractor\bin\
    Remove-Item -Recurse -Force -ErrorAction Ignore  .\CodegenCS.DbSchema.Extractor\obj\
}


# The following libraries are all part of dotnet-codegencs tool...

& $msbuild ".\CodegenCS.DbSchema.Extractor\CodegenCS.DbSchema.Extractor.csproj" `
           /t:Restore /t:Build                                                  `
           '/p:targetFrameworks="netstandard2.0;net472;net5.0"'                 `
           /p:Configuration=$configuration                                      `
           /p:IncludeSymbols=true                                               `
           /p:SymbolPackageFormat=snupkg                                        `
           /verbosity:minimal                                                   `
           /p:ContinuousIntegrationBuild=true


& $msbuild ".\CodegenCS.DbSchema.Templates\CodegenCS.DbSchema.Templates.csproj" `
           /t:Restore /t:Build                                                  `
           '/p:targetFrameworks="netstandard2.0;net472;net5.0"'                 `
           /p:Configuration=$configuration                                      `
           /p:IncludeSymbols=true                                               `
           /p:SymbolPackageFormat=snupkg                                        `
           /verbosity:minimal                                                   `
           /p:ContinuousIntegrationBuild=true
           
dotnet restore CodegenCS.TemplateBuilder\CodegenCS.TemplateBuilder.csproj
& $msbuild ".\CodegenCS.TemplateBuilder\CodegenCS.TemplateBuilder.csproj" `
           /t:Restore /t:Build                                                  `
           '/p:targetFrameworks="netstandard2.0;net472;net5.0"'                 `
           /p:Configuration=$configuration                                      `
           /p:IncludeSymbols=true                                               `
           /p:SymbolPackageFormat=snupkg                                        `
           /verbosity:minimal                                                   `
           /p:ContinuousIntegrationBuild=true

dotnet restore CodegenCS.TemplateLauncher\CodegenCS.TemplateLauncher.csproj
& $msbuild ".\CodegenCS.TemplateLauncher\CodegenCS.TemplateLauncher.csproj" `
           /t:Restore /t:Build                                                  `
           '/p:targetFrameworks="netstandard2.0;net472;net5.0"'                 `
           /p:Configuration=$configuration                                      `
           /p:IncludeSymbols=true                                               `
           /p:SymbolPackageFormat=snupkg                                        `
           /verbosity:minimal                                                   `
           /p:ContinuousIntegrationBuild=true



# dotnet-codegencs (DotnetTool nupkg/snupkg)
& $msbuild ".\dotnet-codegencs\dotnet-codegencs.csproj"   `
           /t:Restore /t:Build /t:Pack                             `
           /p:PackageOutputPath="..\packages-local\"      `
           '/p:targetFrameworks="net5.0"'                 `
           /p:Configuration=$configuration                `
           /p:IncludeSymbols=true                         `
           /p:SymbolPackageFormat=snupkg                  `
           /verbosity:minimal                             `
           /p:ContinuousIntegrationBuild=true

# Now all nuget packages (including the global tool) are in .\packages-local\

# uninstall/reinstall global tool from local dotnet-codegencs.*.nupkg:
dotnet tool uninstall -g dotnet-codegencs
dotnet tool install --global --add-source .\packages-local --no-cache dotnet-codegencs
dotnet-codegencs --version


# Unit tests
dotnet build -c $configuration CodegenCS.Tests\CodegenCS.Tests.csproj
#dotnet test  CodegenCS.Tests\CodegenCS.Tests.csproj