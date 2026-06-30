# Deploys Cloud Functions, bypassing the nodist shim that breaks firebase's
# function-analysis child process (NODIST_PREFIX not inherited in that fork).
$realNode = "C:\Program Files (x86)\Nodist\v-x64\22.23.1"
$env:PATH = ($env:PATH -split ";" | Where-Object { $_ -notmatch "Nodist\\bin" }) -join ";"
$env:PATH = "$realNode;$env:PATH"

node "C:\Program Files (x86)\Nodist\bin\node_modules\firebase-tools\lib\bin\firebase.js" deploy --only functions --force
