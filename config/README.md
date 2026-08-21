# Configuration Contract

Directory ini menyimpan configuration non-secret milik Tomcat Monitoring.
Setiap component configuration dibuat hanya setelah interface runtime dan
validatornya disetujui.

Jangan menyimpan certificate, private key, password, token, credential,
environment file, inventory, atau runtime-generated data di bawah directory
ini. Material tersebut diberikan melalui runtime secret injection yang telah
disetujui.
