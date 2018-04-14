#! /bin/bash

SCRIPTLOCATION="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

check_internet(){ 
	ping 8.8.8.8 -c 5 -W 1 &>/dev/null
	return $?
}


remote_status(){
	# exit codes: (0=up-to-date, 1|2=diverged, 3|4=error)
	if check_internet; then
		git fetch "$1" || (echo "fetch failed" && exit 3)
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
		echo "Not connected to internet"
		return 3
	fi
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
		echo "Checking for updates for $1 ..."
		remote_status "$2" "$3"
		STATUS=$? # 0=good, 1-2=bad, 3=offline
		if [[ $STATUS -eq 3 ]]; then # failed
			echo "Checking for update failed, connect to internet to allow updates"
			STATUS=$LASTCHECKSTATUS
		fi
		echo "$(date +%s)s$STATUS" > ".last-checked"
		cd "$where" || exit 3
		return $STATUS

	else
		cd "$where" || exit 3
		return $LASTCHECKSTATUS
	fi

}


require_clean(){
	if ! [[ -z "$(git status --porcelain)" ]]; then
		git status
		echo "please commit changes here before starting next task"
		exit 1
	fi
}


check_for_changes $SCRIPTLOCATION origin master 12  # check every 12 hours
CODE=$?
if [[ $CODE -eq 0 ]]; then
	echo "code-review.sh is up to date!"
else
	echo "code-review.sh is out-of-date please run code-review.sh update"
fi


case $1 in
	'install' )
		if [[ $# -ne 1 ]]; then
			echo "incorrect usage"
			echo "USAGE: ./code-review.sh install"
			exit 1
		fi
		HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
		if [[ -f "$HOME/.bashrc" ]]; then
			echo "PATH="'$PATH:"'"$HERE"'"' >> "$HOME/.bashrc"
			echo "added this script to ~/.bashrc, now run source ~/.bashrc"
		fi
		if [[ -f "$HOME/.tcshrc" ]]; then
			echo "setenv PATH "'${PATH}:"'"$HERE"'"' >> "$HOME/.tcshrc"
			echo "added this script to ~/.tcshrc, now run source ~/.tcshrc"
		fi
		echo "Script has been added to you PATH, meaning you can run code-review.sh from anywhere"
		exit 0
		;;
	'update' )
		if [[ $# -ne 1 ]]; then
			echo "incorrect usage"
			echo "USAGE: code-review.sh update"
			exit 1
		fi
		cd $SCRIPTLOCATION &&
		git checkout master &&
		git fetch --all &&
		git reset --hard origin/master &&
		check_for_changes $SCRIPTLOCATION origin master 0 &&  # check immediately
		exit 0
		;;
	'version' )
		if [[ $# -ne 1 ]]; then
			echo "incorrect usage"
			echo "USAGE: code-review.sh version"
			exit 1
		fi
		cd $SCRIPTLOCATION &&
		echo "latest version number: $(git describe --long --tags --dirty --always --match "v*")"
		echo "latest tag: $(git describe --abbrev=0 --tags)"
		echo "current branch: $(git rev-parse --abbrev-ref HEAD)"
		echo "commit hash: $(git rev-parse --verify HEAD)"
		exit 0
		;;
esac


if ! git status --porcelain &> /dev/null; then
	echo "Not in a git repository, exiting" && exit 1
fi
TOPLEVEL="$(git rev-parse --show-toplevel)"
REPONAME="$(basename -s .git `git config --get remote.origin.url`)"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

ORIGIN="$(git config --get remote.origin.url)"
UPSTREAM_ORIGIN="$(git config --get remote.upstream.url)"
NO_UPSTREAM=$?
if [[ "$(git config --get remote.origin.url)" != "git@"* ]]; then
	PREFIX="https://github.com/"
else
	PREFIX="git@github.com:"
fi
HTTPS="https://github.com/"
GITHUB_ORIGIN="${ORIGIN/$PREFIX/$HTTPS}"
GITHUB_ORIGIN="${GITHUB_ORIGIN::-4}"
GITHUB_UPSTREAM="${UPSTREAM_ORIGIN/$PREFIX/$HTTPS}"
if [[ $NO_UPSTREAM -ne  0 ]]; then
	echo "Upstream repository not found, run code-review.sh first-time-setup <UPSTREAM_ORGANISATION>"
else
	GITHUB_UPSTREAM="${GITHUB_UPSTREAM::-4}" # chop of .git if there is an upstream repo
	check_for_changes "$TOPLEVEL" upstream master 12
	CODE=$?
	if [[ $CODE -eq 0 ]]; then
		echo "No new upstream changes to this repository!"
	else
		echo "The repository $TOPLEVEL is out-of-date to receive upstream changes"
		echo "Run code-review.sh pull-tasks to get the latest update"
		echo "Then run code-review.sh update-task <TASK-NAME> to update the task you are working on"
	fi
fi

GITHUB_USERNAME="${ORIGIN/$PREFIX}"
GITHUB_USERNAME="${GITHUB_USERNAME%/*}"



case $1 in
	'first-time-setup' )
		if [[ $# -ne 2 ]]; then
			echo "incorrect usage"
			echo "USAGE: code-review.sh first-time-setup <UPSTREAM_ORGANISATION>"
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
		check_for_changes "$TOPLEVEL" upstream master 0  # update upstream status
		echo "Linked to upstream repository, created solutions branch." &&
		echo "Consider adding this script to your path in your .tcshrc/.bashrc using code-review.sh install for easy access when working" &&
		echo "Now use code-review.sh start-task to start the latest task" &&
		exit 0) ||
		echo "Failed: have you already done first-time-setup?" && exit 0
		;;
	'view-solution' )
		if [ $# -gt 3 ] || [ $# -lt 2 ]; then
			echo "incorrect usage"
			echo "USAGE: code-review.sh view-solution <USERNAME> [<BRANCH>=solutions]"
			exit 1
		elif [[ $# -eq 3 ]]; then
			USERNAME=$2
			BRANCH=$3
		elif [[ $# -eq 2 ]]; then
			USERNAME=$2
			BRANCH="solutions"
		else
			echo "incorrect usage"
			echo "USAGE: code-review.sh view-solution <USERNAME> [<BRANCH>=solutions]"
			exit 1
		fi
		require_clean &&
		ORIGINNAME="$(git config --get remote.origin.url)"
		REMOTENAME="$PREFIX$USERNAME/$REPONAME.git"
		if [[ "$ORIGINNAME" -eq "$REMOTENAME" ]]; then
			echo "That is your own fork. Checking out your solutions"
			git checkout solutions && exit 0
		fi
		echo 'adding repository and checking out' &&
		git remote add "$USERNAME" "$REMOTENAME" &&
		git fetch "$USERNAME" "$BRANCH" &&
		(git checkout -b "$USERNAME-$BRANCH" "$USERNAME/$BRANCH") || (git checkout "$USERNAME-$BRANCH" && git reset --hard FETCH_HEAD && git clean -df) &&
		exit 0
		;;
	'pull-tasks' )
		if [[ $# -ne 1 ]]; then
			echo "incorrect usage"
			echo "USAGE: code-review.sh pull-tasks"
			exit 1
		fi
		require_clean &&
		cd "$TOPLEVEL" &&
		git fetch upstream &&
		git checkout master && 
		git merge upstream/master &&
		git checkout $CURRENT_BRANCH &&
		check_for_changes "$TOPLEVEL" upstream master 0 &&  # check immediately 
		echo "run code-review.sh update-task <TASK-NAME> if you need to."
		exit 0
		;;
	'start-task' )
		if [[ $# -ne 2 ]]; then
			echo "incorrect usage"
			echo "USAGE: code-review.sh start-task <TASK-NAME>"
			exit 1
		fi
		require_clean &&
		cd "$TOPLEVEL" &&
		git fetch upstream &&
		git checkout master && 
		git merge upstream/master &&
		check_for_changes "$TOPLEVEL" upstream master 0 &&
		git checkout -b "$2-solution" && 
		cd "Task $2" &&
		echo "Now on branch $2-solution, do your work in the task folder and then run code-review.sh finish-task to commit and upload" &&
		exit 0
		;;
	'finish-task' )
		if [[ $# -ne 2 ]]; then
			echo "incorrect usage"
			echo "USAGE: code-review.sh finish-task <TASK-NAME>"
			exit 1
		fi
		read -p "Submit finished task $2? [enter]"
		require_clean &&
		cd "$TOPLEVEL" &&
		git checkout solutions &&
		git merge "$2-solution" -m "finish $2-solution" &&
		git push --set-upstream origin solutions &&
		echo "Now got to $GITHUB_UPSTREAM/compare/solutions-$GITHUB_USERNAME...$GITHUB_USERNAME:$2-solution?expand=1 to open a pull request" &&
		echo "Done!" &&
		exit 0
		;;
	'update-task' )
		if [[ $# -ne 2 ]]; then
			echo "incorrect usage"
			echo "USAGE: code-review.sh update-task <TASK-NAME>"
			exit 1
		fi
		read -p "This will pull any changes from the remote repository and merge them with your current work on Task $2. Continue? [enter]"
		require_clean &&
		cd "$TOPLEVEL" &&
		(git rebase master "$2-solution" &&
		git checkout "$CURRENT_BRANCH" &&
		echo "Update succeeded, continue as you were. You may notice some changes from upstream!") || (echo "update failed...") &&
		exit 0
		;;
	'develop' )
		case $2 in
			'create-task' )
				if [[ $# -ne 3 ]]; then
					echo "incorrect usage"
					echo "USAGE: code-review.sh develop create-task <TASK-NAME>"
					exit 1
				fi
				require_clean &&
				echo "We will now develop the new task-$3 by branching from the development branch (where all experiments/works in progress should branch from)" &&
				echo "The master branch should be kept working" &&
				git checkout master &&
				git branch "task-$3/finalised/task" &&
				git checkout master &&
				git branch "task-$3/finalised/solution" &&
				git checkout master &&
				git checkout -b "task-$3/develop" &&
				cd $TOPLEVEL && mkdir "Task $3" &&
				echo "Summary" &&
				echo "=======" &&
				echo "The current branch task-$3/develop has been created for you."
				echo "Now make the task (including the solution) in the Task $3 folder." &&
				echo "If you need to work on something else, feel free to checkout other branches. You can resume work here by using git checkout task-$3/develop"
				echo "Commit and then use code-review.sh develop begin-finalise-task $3 once you're done." &&
				exit 0
				;;
			'begin-finalise-task' )
				if [[ $# -ne 3 ]]; then
					echo "incorrect usage"
					echo "USAGE: code-review.sh develop begin-finalise-task <TASK-NAME>"
					exit 1
				fi
				require_clean &&
				cd "$TOPLEVEL" &&
				git checkout "task-$3/develop" &&
				git branch "task-$3/solution" &&
				git checkout -b "task-$3/task" &&
				echo "Summary" &&
				echo "=======" &&
				echo "Your task and its solution have been saved to the task-$3/solution branch" &&
				echo "You are now on the task-$3/task branch"
				echo "Any changes you make here will only be reflected in the task branch (i.e. the one without the solution)"
				echo "Now:" &&
				echo "   1. Remove your solution to the task from the task folder" &&
				echo "   2. Commit the changes"  && 
				echo "   3. Use code-review.sh develop end-finalise-task $3 to finish" &&
				exit 0
				;;
			'end-finalise-task' )
				if [[ $# -ne 3 ]]; then
					echo "incorrect usage"
					echo "USAGE: code-review.sh develop end-finalise-task <TASK-NAME>"
					exit 1
				fi
				require_clean &&
				cd "$TOPLEVEL" &&
				git checkout "task-$3/finalised/task" && 
				git merge --squash "task-$3/task" -m "merged task" &&
				git add --all && git commit -m "merged task" &&
				git checkout "task-$3/finalised/solution" &&
				git merge "task-$3/solution" -m "merged solution" &&
				git branch -D "task-$3/task" &&
				git branch -D "task-$3/solution" &&
				git checkout master &&
				echo "Summary" &&
				echo "=======" &&
				echo "Merged the new task (without solution into the finalised task branch" &&
				echo "Merged the new solution to that task into the finalised solution branch" &&
				echo "Deleted the temporary task-$3 solution and task branches" &&
				echo "Returned to the master branch" &&
				echo "Task $3 has been finalised but not published. No one else can see it yet" &&
				echo "Use code-review.sh develop publish-task $3 to publish to github'" &&
				echo "You may need to change directory now since the master branch doesn't know about your task yet (it will after publishing)" &&
				exit 0
			        ;;
			'publish-task' )
				if [[ $# -ne 3 ]]; then
					echo "incorrect usage"
					echo "USAGE: code-review.sh develop publish-task <TASK-NAME>"
					exit 1
				fi
				read -p "This will publish your task-$3 TASK (with no solution) to github. Continue? [enter]"
				require_clean &&
				cd "$TOPLEVEL" &&
				git push --set-upstream origin "task-$3/finalised/task" &&
				echo "Now go to $GITHUB_UPSTREAM/compare/master...$GITHUB_USERNAME:task-$3/finalised/task?expand=1 to open a pull request" &&
				echo "Use code-review.sh develop publish-solutions to publish the SOLUTIONS" &&
				exit 0
				;;
			'publish-solution' )
				if [[ $# -ne 3 ]]; then
					echo "incorrect usage"
					echo "USAGE: code-review.sh develop publish-solution <TASK-NAME>"
					exit 1
				fi
				read -p "This will publish your task-$3 SOLUTION to github. Continue? [enter]"
				require_clean &&
				cd "$TOPLEVEL" &&
				git push --set-upstream origin "task-$3/finalised/solution" &&
				echo "Now go to $GITHUB_UPSTREAM/compare/solutions-$GITHUB_USERNAME...$GITHUB_USERNAME:task-$3/finalised/solution?expand=1 to open a pull request" &&
				exit 0
				;;
			'reopen-finalised-task' )
				if [[ $# -ne 3 ]]; then
					echo "incorrect usage"
					echo "USAGE: code-review.sh develop reopen-finalised-task <TASK-NAME>"
					exit 1
				fi
				require_clean &&
				echo "Warning: reopening and then publishing a task may result in other people losing data if you delete files!"
				read -p "This will repoen edits on task $3 and its solution. Continue? [enter]"
				(git checkout "task-$3/develop" || (echo "task-$3 has not been created yet" && exit 1) ) &&
				echo "Summary" &&
				echo "=======" &&
				echo "You have been returned to the task-$3/develop branch" &&
				echo "Now make the necessary edits to the Task $3 folder." &&
				echo "Commit and then use code-review.sh develop begin-finalise-task $3 once you're done." &&
				exit 0
		esac

esac

echo "incorrect usage"
echo "USAGE: code-review.sh <first-time-setup|view-solution|start-task|finish-task|pull-tasks|update-task>"
echo "       or"
echo "       code-review.sh develop <create-task|finalise-task|publish-task|publish-solution>"
exit 1