#! /bin/bash

# Reset
reset='\033[0m'       # Text Reset
# Regular Colors
Red='\033[1;31m'
Green='\033[1;32m'
Yellow='\033[0;33m'



SCRIPTLOCATION="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

check_internet(){ 
	ping 8.8.8.8 -c 5 -W 1 &>/dev/null
	return $?
}

echo_bad(){
	echo -e "$Red$1$reset"
}

echo_good(){
	echo -e "$Green$1$reset"
}

echo_norm(){
	echo -e "$Yellow$1$reset"
}

remote_status(){
	# exit codes: (0=up-to-date, 1|2=diverged, 3|4=error)
	if check_internet; then
		fetched=$(git fetch "$1" 2>&1)
		if [ $? -ne 0 ]; then
			echo fetched &&
			echo_bad "fetch failed" && 
			exit 3
		fi
		UPSTREAM="$1/$2"
		LOCAL=$(git rev-parse "$2") || exit 4
		REMOTE=$(git rev-parse "$UPSTREAM") || exit 4
		BASE=$(git merge-base @{0} "$UPSTREAM") || exit 4

		if [ "$LOCAL" = "$REMOTE" ]; then
		    return 0
		elif [ "$LOCAL" = "$BASE" ]; then
		    return 1
		else
			return 2
		fi
	else
		echo_bad "Not connected to internet"
		return 3
	fi
}

record_checked_status(){
	# usage: record_checked_status DIRECTORY STATUS-CODE (see above)
	echo "$(date +%s)s$2" > "$1/.last-checked"
}

check_for_changes(){
	# usage: check_for_changes directory remote branch frequency
	FREQ=$4
	where="$(pwd)"
	delimiter="s"
	cd "$1" || exit 3

	if [[ -f ".last-checked" ]]; then
		CONTENTS="$(cat .last-checked)"
		if [[ $CONTENTS = *"$delimiter"* ]]; then
			LASTCHECKDATE="${CONTENTS%%s*}"
			LASTCHECKSTATUS="${CONTENTS#*s}"
		else
			LASTCHECKDATE=$CONTENTS
			LASTCHECKSTATUS=1  # backwards compat - assume out of date
		fi
		NOW=$(date +%s)
		DIFF=$(( NOW - LASTCHECKDATE ))
	else
		DIFF="$(((FREQ+1)*60*60))"
		LASTCHECKSTATUS=1  # assume out of date
	fi

	if [[ $DIFF -gt "$((60*60*FREQ))" ]]; then
		echo_norm "Checking for updates for $1 ..."
		remote_status "$2" "$3"
		STATUS=$? # 0=good, 1-2=bad, 3=offline
		if [[ $STATUS -eq 3 ]]; then # failed
			echo_bad "Checking for update failed, connect to internet to allow updates"
			STATUS=$LASTCHECKSTATUS
		fi
		record_checked_status "$1" "$STATUS" 
		cd "$where" || exit 3
		return $STATUS

	else
		cd "$where" || exit 3
		return $LASTCHECKSTATUS
	fi

}


require_clean(){
	if ! [[ -z "$(git status --porcelain | grep -v .last-checked)" ]]; then
		git status 
		echo_bad "please commit changes here before starting next task"
		exit 1
	fi
}

echo_norm "====<UPDATES>==="
check_for_changes "$SCRIPTLOCATION" origin master 12  # check every 12 hours
CODE=$?
if [[ $CODE -eq 0 ]]; then
	echo_good "code-review.sh is up to date!"
else
	echo_bad "code-review.sh is out-of-date please run 'code-review.sh update'"
fi


case $1 in
	'install' )
		if [[ $# -ne 1 ]]; then
			echo_bad "incorrect usage"
			echo_bad "USAGE: ./code-review.sh install"
			exit 1
		fi
		HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

		touch "$HOME/.bashrc" 
		addition="PATH="'$PATH:"'"$HERE"'"'
		if [[ "$(cat "$HOME/.bashrc")" = *"$addition"* ]]; then
			echo "$addition" >> "$HOME/.bashrc"
			echo_norm "added this script to ~/.bashrc, now run source ~/.bashrc"
		else
			echo_norm "already added to ~/.bashrc"
		fi
		
		touch "$HOME/.tcshrc"
		addition="setenv PATH "'${PATH}:"'"$HERE"'"'
		if [[ "$(cat "$HOME/.tcshrc")" = *"$addition"* ]]; then
			echo "$addition" >> "$HOME/.tcshrc"
			echo_norm "added this script to ~/.tcshrc, now run source ~/.tcshrc"
		else
			echo_norm "already added to ~/.tcshrc"
		fi
		echo_norm "Script has been added to your PATH, meaning you can run code-review.sh from anywhere"
		echo_norm "================"
		exit 0
		;;
	'update' )
		if [[ $# -ne 1 ]]; then
			echo_bad "incorrect usage"
			echo_bad "USAGE: code-review.sh update"
			exit 1
		fi
		cd "$SCRIPTLOCATION" &&
		git checkout master &&
		git fetch --all &&
		git reset --hard origin/master &&
		record_checked_status "$SCRIPTLOCATION" 0 &&
		echo_good "Update complete!" &&
		echo_norm "================" &&
		exit 0
		;;
	'version' )
		if [[ $# -ne 1 ]]; then
			echo_bad "incorrect usage"
			echo_bad "USAGE: code-review.sh version"
			exit 1
		fi
		cd "$SCRIPTLOCATION" &&
		echo_norm "latest version number: $(git describe --long --tags --dirty --always --match "v*")" &&
		echo_norm "latest tag: $(git describe --abbrev=0 --tags)" &&
		echo_norm "current branch: $(git rev-parse --abbrev-ref HEAD)" &&
		echo_norm "commit hash: $(git rev-parse --verify HEAD)" &&
		echo_norm "================" &&
		exit 0
		;;
esac


if ! git status --porcelain &> /dev/null; then
	echo_norm "================" && echo_bad "Not in a git repository, exiting" && exit 1

fi
TOPLEVEL="$(git rev-parse --show-toplevel)"
REPONAME="$(basename -s .git "$(git config --get remote.origin.url)")"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

ORIGIN="$(git config --get remote.origin.url)"
UPSTREAM_ORIGIN="$(git config --get remote.upstream.url)"
NO_UPSTREAM=$?
if [[ "$(git config --get remote.origin.url)" != "git@"* ]]; then
	PREFIX="https://github.com/"
	echo_norm "You are using https, which requires you to enter your password each time you push."
	echo_norm "Consider using ssh which does not require passwords: https://help.github.com/articles/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent/"
else
	PREFIX="git@github.com:"
fi
HTTPS="https://github.com/"
GITHUB_ORIGIN="${ORIGIN/$PREFIX/$HTTPS}"
GITHUB_ORIGIN="${GITHUB_ORIGIN::-4}"
GITHUB_UPSTREAM="${UPSTREAM_ORIGIN/$PREFIX/$HTTPS}"
if [[ $NO_UPSTREAM -ne  0 ]]; then
	echo_bad "Upstream repository not found, Are you in the code-review repository?"
	echo_bad "If you are, then run code-review.sh first-time-setup <UPSTREAM_ORGANISATION>"
	echo_bad "UPSTREAM_ORGANISATION is probably something like herts-astrostudents"
else
	GITHUB_UPSTREAM="${GITHUB_UPSTREAM::-4}" # chop of .git if there is an upstream repo
	check_for_changes "$TOPLEVEL" upstream master 12
	CODE=$?
	if [[ $CODE -eq 0 ]]; then
		echo_good "No new upstream changes to the repository $TOPLEVEL!"
	else
		echo_norm "The repository $TOPLEVEL is out-of-date. Run 'code-review.sh pull-tasks' to receive upstream changes"
		echo_norm "Run code-review.sh pull-tasks to get the latest update"
		echo_norm "Then run code-review.sh rebase-task <TASK-NAME> to update the task you are working on"
	fi
fi
echo_norm "================"

GITHUB_USERNAME="${ORIGIN/$PREFIX}"
GITHUB_USERNAME="${GITHUB_USERNAME%/*}"



pull_tasks(){
	cd "$TOPLEVEL" &&
	(rm ".last-checked" || echo "reset last-checked") &&
	require_clean &&
	git fetch upstream &&
	git checkout master && 
	git merge upstream/master &&
	git push origin master &&
	git checkout "$CURRENT_BRANCH" &&
	record_checked_status "$TOPLEVEL" 0 &&
	echo_good "Your local and remote repositories have been updated successfully!" &&
	echo_norm "[run code-review.sh rebase-task <TASK-NAME> if you need to update a task in progress.]"
}


case $1 in
	'first-time-setup' )
		if [[ $# -ne 2 ]]; then
			echo_bad "incorrect usage"
			echo_bad "USAGE: code-review.sh first-time-setup <UPSTREAM_ORGANISATION>"
			exit 1
		fi
		git config push.default simple
		UPSTREAM_ORGANISATION=$2
		UPSTREAM="$PREFIX$UPSTREAM_ORGANISATION/$REPONAME.git"
		
		git remote add upstream "$UPSTREAM"
		require_clean &&
		(git checkout master &&
		git fetch upstream && 
		git merge upstream/master &&
		(git branch solutions || echo "solutions branch already exists") &&
		git checkout master &&
		record_checked_status "$TOPLEVEL" 0 &&
		echo_good "Linked to upstream repository, created solutions branch." &&
		echo_good "Now use code-review.sh start-task to start the latest task" &&
		echo_norm "Consider adding this script to your path in your .tcshrc/.bashrc using code-review.sh install for easy access when working" &&
		exit 0) ||
		echo_bad "Failed: have you already done first-time-setup?" && exit 0
		;;
	'view-solution' )
		if [ $# -gt 3 ] || [ $# -lt 2 ]; then
			echo_bad "incorrect usage"
			echo_bad "USAGE: code-review.sh view-solution <USERNAME> [<BRANCH>=solutions]"
			exit 1
		elif [[ $# -eq 3 ]]; then
			USERNAME=$2
			BRANCH=$3
		elif [[ $# -eq 2 ]]; then
			USERNAME=$2
			BRANCH="solutions"
		else
			echo_bad "incorrect usage"
			echo_bad "USAGE: code-review.sh view-solution <USERNAME> [<BRANCH>=solutions]"
			exit 1
		fi
		require_clean &&
		ORIGINNAME="$HTTPS$GITHUB_USERNAME/$REPONAME.git" # "$(git config --get remote.origin.url)"
		REMOTENAME="$HTTPS$USERNAME/$REPONAME.git"
		if [[ "$ORIGINNAME" == "$REMOTENAME" ]]; then
			echo_norm "That is your own fork. Checking out your solutions"
			git checkout solutions && exit 0
		fi
		echo_norm 'adding repository and checking out'
		git remote add "$USERNAME" "$REMOTENAME" &>/dev/null
		if [[ $? -eq 0 ]]; then
			git fetch "$USERNAME" 
			git checkout "$USERNAME/$BRANCH"
			if [ $? -eq 0 ]; then
				echo_good "Now on the $BRANCH branch of $USERNAME"
				echo_norm "This is a temporary branch"
				echo_norm "To return to a local branch use git checkout <name>. e.g. git checkout master"
				echo_norm "If you have made any changes you'll need to use git checkout -- ." 
				git remote remove "$USERNAME" &&
				exit 0
			else
				echo_bad "$USERNAME exists but the branch $USERNAME/$BRANCH does not."
				git remote remove "$USERNAME" &&
				exit 1
			fi
		else
			echo_bad "$USERNAME does not exist!" &&
			git remote remove "$USERNAME" &&
			exit 1
		fi
		;;
	'pull-tasks' )
		if [[ $# -ne 1 ]]; then
			echo_bad "incorrect usage"
			echo_bad "USAGE: code-review.sh pull-tasks"
			exit 1
		fi
		pull_tasks &&
		exit 0
		;;
	'start-task' )
		if [[ $# -ne 2 ]]; then
			echo_bad "incorrect usage"
			echo_bad "USAGE: code-review.sh start-task <TASK-NAME>"
			exit 1
		fi
		git checkout -b "$2-solution" &&  
		if [[ -d  "Task $2" ]]; then
			echo_good "Now on branch $2-solution, do your work in the Task $2 folder and then run code-review.sh finish-task to commit and upload" &&
			exit 0
		else
			echo_bad "Task $2 folder does not exist" && 
			git checkout "$CURRENT_BRANCH" &&
			git branch -D "$2-solution" && 
			echo_norm "Deleted redundant branch $2-solution" &&
			echo_bad "There does not seem to be a task folder for Task $2. To pull the new tasks: code-review.sh pull-tasks" &&
			exit 1
		fi		
		;;
	'finish-task' )
		if [[ $# -ne 2 ]]; then
			echo_bad "incorrect usage"
			echo_bad "USAGE: code-review.sh finish-task <TASK-NAME>"
			exit 1
		fi
		read -p "Submit finished task $2? [enter]"
		require_clean &&
		cd "$TOPLEVEL" &&
		git checkout solutions
		if [[ $? -ne 0 ]]; then
			echo_norm "Creating branch 'solutions' from master"
			echo_bad "This probably means that first-time-setup was not run"
			git checkout master &&
			git checkout -b solutions
		fi
		git merge "$2-solution" -m "finish $2-solution" &&
		git push --set-upstream origin solutions &&
		git fetch upstream &&
		if grep -q "upstream/solutions-$GITHUB_USERNAME"'$' <<<"$(git branch -r)"; then
			PRBRANCH="solutions-$GITHUB_USERNAME"
		else
			PRBRANCH="master"
		fi
		echo_good "Success!" &&
		echo_good "Now go to $GITHUB_UPSTREAM/compare/$PRBRANCH...$GITHUB_USERNAME:solutions?expand=1 to open a pull request" &&
		exit 0
		;;
	'rebase-task' )
		if [[ $# -ne 2 ]]; then
			echo_bad "incorrect usage"
			echo_bad "USAGE: code-review.sh rebase-task <TASK-NAME>"
			exit 1
		fi
		read -p "This will pull any changes from the remote repository and merge them with your current work on Task $2. Continue? [enter]"
		require_clean &&
		cd "$TOPLEVEL" &&
		git checkout "$2-solution" &&
		git merge master
		if [[ $? -ne 0 ]]; then
			echo_bad "rebase failed..."
			echo_bad "The maintainer is really sorry about that! :("
			echo_bad "You will need to fix the conflicts present in the files below"
			echo_norm "To do that simply choose which changes to keep in the files"
			echo_norm "Here's an example. The contents of an example file which has conflicts is displayed below:"
			echo 
			echo -e "<<<<<<< HEAD\nfrom mistake import terrible_idea as function\nfunction(data)\n=======\nfrom better import good_idea as function\n>>>>>>> master"
			echo
			echo_norm "below the ======, there is the fixed file from github."
			echo_norm "above the ====== is your version"
			echo_norm "In this case we would amend the file to "
			echo 
			echo -e "from better import good_idea as function\nfunction(data)"
			echo
			echo 'Run git commit -am "fixed conflict" when youre finished'
			echo_norm "Good luck!"
			exit 0
		fi
		git checkout "$CURRENT_BRANCH" &&
		echo_good "Rebase succeeded, continue as you were. You may notice some changes from upstream!" &&
		exit 0
		;;
	'develop' )
		case $2 in
			'create-task' )
				if [[ $# -ne 3 ]]; then
					echo_bad "incorrect usage"
					echo_bad "USAGE: code-review.sh develop create-task <TASK-NAME>"
					exit 1
				fi
				require_clean &&
				echo_norm "We will now develop the new task-$3 by branching from the development branch (where all experiments/works in progress should branch from)" &&
				echo_norm "The master branch should be kept working" &&
				git checkout master &&
				git branch "task-$3/finalised/task" &&
				git checkout master &&
				git branch "task-$3/finalised/solution" &&
				git checkout master &&
				git checkout -b "task-$3/develop" &&
				cd "$TOPLEVEL" && mkdir "Task $3" &&
				echo_good "Success!" &&
				echo_norm "Summary" &&
				echo_norm "=======" &&
				echo_norm "The current branch task-$3/develop has been created for you."
				echo_norm "Now make the task (including the solution) in the Task $3 folder." &&
				echo_norm "If you need to work on something else, feel free to checkout other branches. You can resume work here by using git checkout task-$3/develop"
				echo_norm "Commit and then use code-review.sh develop begin-finalise-task $3 once you're done." &&
				exit 0
				;;
			'begin-finalise-task' )
				if [[ $# -ne 3 ]]; then
					echo_bad "incorrect usage"
					echo_bad "USAGE: code-review.sh develop begin-finalise-task <TASK-NAME>"
					exit 1
				fi
				require_clean &&
				cd "$TOPLEVEL" &&
				git checkout "task-$3/develop" &&
				git branch "task-$3/solution" &&
				git checkout -b "task-$3/task" &&
				echo_good "Success!" &&
				echo_norm "Summary" &&
				echo_norm "=======" &&
				echo_norm "Your task and its solution have been saved to the task-$3/solution branch" &&
				echo_norm "You are now on the task-$3/task branch"
				echo_norm "Any changes you make here will only be reflected in the task branch (i.e. the one without the solution)"
				echo_norm "Now:" &&
				echo_norm "   1. Remove your solution to the task from the task folder" &&
				echo_norm "   2. Commit the changes"  && 
				echo_norm "   3. Use code-review.sh develop end-finalise-task $3 to finish" &&
				echo_norm "If you make a mistake you can always reset back to where you finished creating the task by using"
				echo_norm "code-review.sh develop reopen-finalised-task $3"
				exit 0
				;;
			'end-finalise-task' )
				if [[ $# -ne 3 ]]; then
					echo_bad "incorrect usage"
					echo_bad "USAGE: code-review.sh develop end-finalise-task <TASK-NAME>"
					exit 1
				fi
				require_clean &&
				cd "$TOPLEVEL" &&
				git checkout "task-$3/finalised/task" && 
				git merge --squash "task-$3/task" -m "merged task" --strategy-option theirs
				if grep -q "conflict" <<<"$(git diff --check)"; then
					echo_bad "I'm afraid that there have been some conflicts. Please fix them before running end-finalise-task again!"
					exit 0
				fi
				git add --all && git commit -m "merged task" &&
				git checkout "task-$3/finalised/solution" &&
				git merge "task-$3/solution" -m "merged solution" --strategy-option theirs
				if grep -q "conflict" <<<"$(git diff --check)"; then
					echo_bad "I'm afraid that there have been some conflicts. Please fix them before running end-finalise-task again!"
					exit 0
				fi
				git branch -D "task-$3/task" &&	
				git branch -D "task-$3/solution" &&
				git checkout master &&
				echo_good "Success!"
				echo_norm "Summary" &&
				echo_norm "=======" &&
				echo_norm "Merged the new task (without solution into the finalised task branch" &&
				echo_norm "Merged the new solution to that task into the finalised solution branch" &&
				echo_norm "Deleted the temporary task-$3 solution and task branches" &&
				echo_norm "Returned to the master branch" &&
				echo_norm "Task $3 has been finalised but not published. No one else can see it yet" &&
				echo_norm "Use code-review.sh develop publish-task $3 to publish to github'" &&
				echo_norm "You may need to change directory now since the master branch doesn't know about your task yet (it will after publishing)" &&
				exit 0
			        ;;
			'publish-task' )
				if [[ $# -ne 3 ]]; then
					echo_bad "incorrect usage"
					echo_bad "USAGE: code-review.sh develop publish-task <TASK-NAME>"
					exit 1
				fi
				read -p "This will publish your task-$3 TASK (with no solution) to github. Continue? [enter]"
				require_clean &&
				cd "$TOPLEVEL" &&
				git push --set-upstream origin "task-$3/finalised/task" &&
				echo_good "Success! Your task-$3 has been pushed to github" &&
				echo_norm "Now go to $GITHUB_UPSTREAM/compare/master...$GITHUB_USERNAME:task-$3/finalised/task?expand=1 to open a pull request" &&
				echo_norm "Use code-review.sh develop publish-solutions to publish the SOLUTIONS" &&
				exit 0
				;;
			'publish-solution' )
				if [[ $# -ne 3 ]]; then
					echo_bad "incorrect usage"
					echo_bad "USAGE: code-review.sh develop publish-solution <TASK-NAME>"
					exit 1
				fi
				read -p "This will publish your task-$3 SOLUTION to github. Continue? [enter]"
				require_clean &&
				cd "$TOPLEVEL" &&
				git push --set-upstream origin "task-$3/finalised/solution" &&
				echo_good "Success! Your solution to task-$3 has been pushed to github" &&
				echo_norm "Now go to $GITHUB_UPSTREAM/compare/solutions-$GITHUB_USERNAME...$GITHUB_USERNAME:task-$3/finalised/solution?expand=1 to open a pull request" &&
				exit 0
				;;
			'reopen-finalised-task' )
				if [[ $# -ne 3 ]]; then
					echo_bad "incorrect usage"
					echo_bad "USAGE: code-review.sh develop reopen-finalised-task <TASK-NAME>"
					exit 1
				fi
				require_clean &&
				echo_norm "Warning: reopening and then publishing a task may result in other people losing data if you delete files!"
				read -p "This will repoen edits on task $3 and its solution. Continue? [enter]"
				(git checkout "task-$3/develop" || (echo_bad "task-$3 has not been created yet" && exit 1) ) &&
				echo_good "task-$3 has been reopened"
				echo_norm "Summary" &&
				echo_norm "=======" &&
				echo_norm "You have been returned to the task-$3/develop branch" &&
				echo_norm "Now make the necessary edits to the Task $3 folder." &&
				echo_norm "Commit and then use code-review.sh develop begin-finalise-task $3 once you're done." &&
				exit 0
		esac
esac

echo_bad "incorrect usage"
echo_bad "USAGE:"
echo_bad "  Commands for working on tasks:" 
echo_bad "      code-review.sh first-time-setup"
echo_bad "                     view-solution"
echo_bad "                     start-task"
echo_bad "                     finish-task"
echo_bad "                     pull-tasks"
echo_bad "                     rebase-task"
echo
echo_bad "  Commands for developing new tasks:"
echo_bad "      code-review.sh develop create-task"
echo_bad "                             begin-finalise-task"
echo_bad "                             end-finalise-task"
echo_bad "                             publish-task"
echo_bad "                             publish-solution"
echo_bad "                             reopen-finalised-task"
echo
echo_bad "Example: To start work on a new task: code-review.sh start-task 7"
echo_bad "Example: To create a new task for the group: code-review.sh develop create-task 7"
exit 1