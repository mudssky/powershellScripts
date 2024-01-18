param(
	[switch]$local,
	[switch]$showCurrent
)

if ($showCurrent) {
	git config  user.name 	
	git config  user.email
	exit	
}
if ($local) {
	git config  user.name "mudssky"
	git config  user.email "mudssky@gmail.com"
	exit
}
git config --global user.name "mudssky"
git config --global user.email "mudssky@gmail.com"