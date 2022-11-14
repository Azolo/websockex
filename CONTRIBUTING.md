# Contributing to Websockex

Here are some guidelines on how to contribute to Websockex. Please take some time 
and read through this before creating a pull request. Your contributions are 
hugely important to the success of Websockex, and all help is greatly appreciated!

- [Issues Tracker](#issues-tracker)
- [Bug Reports](#bug-reports)
- [Feature Requests](#feature-requests)
- [Contributing](#contributing)
- [Pull Requests](#pull-requests)

## Issues Tracker

I use the issues tracker to do the following things:

* **feature requests**
* **[bug reports](#bug-reports)**
* **[submitting pull requests](#pull-requests)**

Please leave a comment on the issue you are working on before starting, so that everyone knows
it's off limits. You don't need to wait for a response before starting, but the comment will
help ensure no duplicate work.

## Bug Reports

A bug is a _demonstrable problem_ that is caused by the code in the repository. The bug must
be reproducible against the master branch.

Guidelines for bug reports:

1. **Use the GitHub issue search**

2. **Check if the issue has been fixed**

Please try to be as detailed as possible in your report. Include information about
your operating system, your Erlang and Elixir versions (i.e. 17.1.2, or 1.0.2).
Provide steps to reproduce the issue as well as the outcome you were expecting. All
these details will help other developers to find and fix the bug.

## Feature Requests

Feature requests can be made by opening an issue as a request for consideration.
Prefix the title with `[FEATURE]`.

Feature requests will be discussed and decided on whether or not it 
fits within the goals of the project. If it does, a moderator will add a feature label.

## Contributing

The following *must* be done for all PRs where possible:

- Functions must have docs -- see existing code for examples of what is expected.
- Functions must have typespecs -- Please re-use existing typespecs where applicable.
- Use comments -- but only use them sparingly on code that is not self-evident.
- Format Code -- Ensure your code is formatted and written to match the existing style of the project.
- Tests -- Make sure you write tests to cover the code you wrote. If zero tests are needed, make
  sure you mention that in your PR.

Please remember to run the full test suite with `mix test`.

When tests pass, you are ready to send a PR!


## Pull requests

**IMPORTANT**: By submitting a patch, you agree that your work will be
licensed under the license used by the project.

The recommended process is as follows: 

1. [Fork](http://help.github.com/fork-a-repo/) the project, clone your fork,
   and configure the remotes:

   ```bash
   # Clone your fork of the repo into the current directory
   git clone https://github.com/<your-username>/websockex
   # Navigate to the newly cloned directory
   cd websockex
   # Assign the original repo to a remote called "upstream"
   git remote add upstream https://github.com/Azolo/websockex
   ```

2. If you cloned a while ago, get the latest changes from upstream:

   ```bash
   git checkout master
   git pull upstream master
   ```

3. Create a new topic branch (off of `master`) to contain your feature, change,
   or fix.

   **IMPORTANT**: Making changes in `master` is frowned upon. You should always
   keep your local `master` in sync with upstream `master` and make your
   changes in feature branches.

   ```bash
   git checkout -b <feature-branch-name>
   ```

4. Commit your changes in a logical manner. Keep your commit message short and to the point.

5. Make sure all the tests are still passing.

   ```bash
   mix test
   ```

6. Push your feature branch up to your fork:

   ```bash
   git push origin <feature-branch-name>
   ```

7. [Open a Pull Request](https://help.github.com/articles/using-pull-requests/)
    with a clear title and description.

8. If you haven't updated your pull request for a while, you should consider
   rebasing on master and resolving any conflicts.

   **IMPORTANT**: You should always `git rebase` on `master` to bring your changes up
   to date when necessary.

   ```bash
   git checkout master
   git pull upstream master
   git checkout <your-feature-branch>
   git rebase master
   ```

Thank you for your contributing to `Websockex`!

