# Preserve the .bash_history file, because it occasionally gets truncated

if [ -d $HOME/.history -a -d $HOME/.history/.git ]; then
    cp $HOME/.bash_history $HOME/.history/.bash_history
    (
	cd $HOME/.history
	git commit -m "Automated commit from ~/.bash_logout" .bash_history
    )
fi
