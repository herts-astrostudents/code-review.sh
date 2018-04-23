# code-review.sh
Script to use code-review with 

This script facilitates the automatic handling of the branching and merging of tasks and their solutions. 

The idea is that each person (with their own fork) works on the task on its own branch e.g. The branch "7-solution" is for "Task 7". 
When the task is finished, it is pushed to github and then a pull request is made on the site to say that it is done. The solutions can then be quickly viewed in the code review session.

## Task Flow:
Install the `code-review.sh script` in your preferred directory (not the same as the code-review directory!!):

    git clone https://github.com/herts-astrostudents/code-review.sh && cd code-review.sh && chmod +x code-review.sh && ./code-review.sh install

## Doing the tasks
The steps below show you how to do a task that has been put up on github. `<NAME>` is just the name of the branch that you are doing your task on. So if the task has a folder called `Task 6` use `6` as `<NAME>`.

0. First time setup `code-review.sh first-time-setup herts-astrostudents` (run this only once ever)
1. `code-review.sh start-task <NAME>`
2. Do the task, using git to track progress if you want
3. `code-review.sh finish-task <NAME>`
4. "Submit a pull request" to `herts-astrostudents` on github (pull requests are how people submit improvements for inspection on github)

To checkout other people's pull requests during the session, run `git pr <pull request number> upstream` or use `code-review.sh view <USERNAME>` to directly view their solution branch without a pull request.


## Writing a task for the group
For anyone who wants to write a task for the group:
The goal is to have a separate branch for you task and then merge it with the master branch.
Each task should have a `readme.md` to explain what to to and a script to run to test/produce the desired output.
i.e. it should contain `task.py` and `solution.py`.
We are also working exclusively in python and miscellaneous command line applications. No IDL!

1. `code-review.sh develop create-task <NAME>` (this will make a folder called `Task <NAME>`)
2. Write the task in the task folder along with the solution!
3. `code-review.sh develop begin-finalise-task <NAME>`
4. Remove the solution so only the task remains!
5. `code-review.sh develop end-finalise-task <NAME>`
5. `code-review.sh develop publish-task <NAME>`
6. Submit a pull request to `herts-astrostudents` for the branch `task-<NAME>` on github and the maintainer will merge it.
7.  `code-review.sh develop publish-solution <NAME>` to publish your solution like everyone else
8. Submit a pull request to `herts-astrostudents` for the branch `solutions` on github and the maintainer will merge it.
9. Go to the code review session


## Repository Maintenance (admin)
For the admin(s) maintaining this repo:
The goal is to have everyone push their own repo to their own branch on the upstream repo (so everyone can easily access the solutions).

1. Look at pull requests for written tasks 
    * Merge onto the master branch 
1. Look at the solution pull requests. 
    * Create a new branch from the master (named `solution-<PERSON>`) (on github)
    * Direct the pull request to their own personalised solution branch (so make sure that `<person1>` has their solution pull request against `solution-<person1>`)
1. Merge the pull request into the personalised branch (on github)
1. DO NOT PUBLISH SOLUTIONS TO THE DEVELOPMENT OR MASTER BRANCHES, do them on their own branches.

The git tree should have branches:

* *Master* (Do not edit directly. Should only be merged with!)
* *solution-person1* (only for the solutions of person 1)
* *solution-person2* (only for the solutions of person 2)
* etc...
