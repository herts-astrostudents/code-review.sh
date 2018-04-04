#! /bin/bash

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
			echo "added this script to ~/.bashrc, now source"
		fi
		if [[ -f "$HOME/.tcshrc" ]]; then
			echo "setenv PATH "'${PATH}:"'"$HERE"'"' >> "$HOME/.tcshrc"
			echo "added this script to ~/.tchsrc, now source"
		fi
		exit 0
		;;
	'update' )
		if [[ $# -ne 1 ]]; then
			echo "incorrect usage"
			echo "USAGE: code-review.sh update"
			exit 1
		fi
		cd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" &&
		git pull &&		
		exit 0
		;;
esac


REPONAME="$(basename -s .git `git config --get remote.origin.url`)"
if [[ "$(git config --get remote.origin.url)" != "git@"* ]]; then
	PREFIX="https://github.com/"
else
	PREFIX="git@github.com:"
fi
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
TOPLEVEL="$(git rev-parse --show-toplevel)"


require_clean(){
	if ! [[ -z "$(git status --porcelain)" ]]; then
		git status
		echo "please commit changes here before starting next task"
		exit 1
	fi
}


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
		if [[ ORIGINNAME -eq REMOTENAME ]]; then
			echo "That is your own fork. Checking out your solutions"
			git checkout solutions && exit 0
		fi
		echo 'adding repository and checking out'
		git remote add "$USERNAME" REMOTENAME &&
		git fetch "$USERNAME" "$BRANCH" &&
		(git checkout -b "$USERNAME-$BRANCH" "$USERNAME/$BRANCH") || (git checkout "$USERNAME-$BRANCH" && git reset --hard FETCH_HEAD && git clean -df) &&
		exit 0
		;;
	'pull-tasks' )
		if [[ $# -ne 2 ]]; then
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
		git checkout -b "$2-solution" && 
		cd "Task $2" &&
		echo "Now on branch $2-solution, do your work in the task folder and then run code-review.sh finish-task to commit and upload"
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
		echo "Now open a pull request on github.com and your're done!"
		exit 0
		;;
	'update-task' )
		if [[ $# -ne 2 ]]; then
			echo "incorrect usage"
			echo "USAGE: code-review.sh update-task <TASK-NAME>"
			exit 1
		fi
		read -p "This will pull any changes from the remote repository. Continue? [enter]"
		require_clean &&
		cd "$TOPLEVEL" &&
		(git checkout "$2-solution" && 
		git fetch upstream && 
		git checkout master && 
		git merge upstream/master &&
		git rebase master "$2-solution" &&
		echo "Update succeeded, continue as you were. You may notice some changes from upstream!") || (echo "update failed...") &&
		git checkout "$CURRENT_BRANCH" &&
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
				git checkout master &&
				git fetch upstream && 
				git merge upstream/master &&
				git branch "task-$3" &&
				git checkout -b "$3-solution" &&
				mkdir "Task $3" && cd "Task $3"  && 
				echo "Now make the task (including the solution) in the Task $3 folder." &&
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
				git checkout "task-$3" &&
				git merge --squash "$3-solution" &&
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
				git checkout "$3-solution" && git rebase "task-$3" &&
				git checkout solutions &&
				git merge "$3-solution" -m "finish $3-solution" &&
				echo "Task $3 has been finalised, now on solutions branch" &&
				echo "Now use code-review.sh develop publish-task $3 to publish to github'" &&
				echo "If you find that you need to change the task/solution, use code-review.sh develop edit-task $3" &&
				exit 0
			        ;;
			'publish-task' )
				if [[ $# -ne 3 ]]; then
					echo "incorrect usage"
					echo "USAGE: code-review.sh develop publish-task <TASK-NAME>"
					exit 1
				fi
				read -p "This will publish your TASK (with no solution) to github. Continue? [enter]"
				require_clean &&
				cd "$TOPLEVEL" &&
				(git push --set-upstream origin "task-$3" || exit 1) &&
				echo "Now open a pull request against $UPSTREAM on github for task-$3" &&
				echo "Use code-review.sh develop publish-solution $3 to publish the SOLUTION to this task later" &&
				exit 0
				;;
			'publish-solution' )
				if [[ $# -ne 3 ]]; then
					echo "incorrect usage"
					echo "USAGE: code-review.sh develop publish-task <TASK-NAME>"
					exit 1
				fi
				read -p "This will publish your SOLUTION ($3-solution) for task-$3 to github. Continue? [enter]"
				require_clean &&
				cd "$TOPLEVEL" &&
				(git push --set-upstream origin solutions || exit 1) &&
				echo "Now open a pull request against $UPSTREAM on github for task-$3"
				exit 0
				;;
			'edit-task' )
				if [[ $# -ne 3 ]]; then
					echo "incorrect usage"
					echo "USAGE: code-review.sh develop edit-task <TASK-NAME>"
					exit 1
				fi
				read -p "This will repoen edits on task $3 and its solution. Continue? [enter]"
				require_clean &&
				cd "$TOPLEVEL" &&
				git checkout "$3-solution" &&
				echo "Now perform your edits to the task & solution." &&
				echo "Run code-review.sh develop begin-finalise-task $3 when done" &&
				echo "Warning: if you've published this task, people may be working on it. If you delete template files that were" &&
				echo "previously published, they may lose their work" &&
				exit 0
		esac

esac

echo "incorrect usage"
echo "USAGE: code-review.sh <first-time-setup|view-solution|start-task|finish-task|update-task>"
echo "       or"
echo "       code-review.sh develop <create-task|finalise-task|publish-task|publish-solution|edit-task>"
exit 1