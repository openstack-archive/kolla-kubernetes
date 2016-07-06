================================
Contributing to kolla-kubernetes
================================

.. include:: ../../CONTRIBUTING.rst


Documentation Patches
=====================

Before submitting a documentation patch, please build and review your edits
from a web browser.

The reStructuredText_ files under ./doc/source will compile into HTML pages
under ./doc/build/html.

::

    # Build the docs
    tox -e docs-constraints -v

    # Preview the locally-generated HTML pages within a web browser
    open ./doc/build/html/index.html

    # Create a branch - common branch naming for docs follows the
    #   blueprint name but this is not enforced
    git checkout -b bp/documentation-initialization

    # Subsequent independent changes are commonly named
    #   bp/documentation-initialization-X
    #   where X is monotomically increasing
    # Edits to the same commit use 'git commit --amend'

    # Verify the scope of your changes is to the files you modified
    git status

    # Ensure that the commit message references the blueprint
    # by adding this line to the commit message:
    # Partially-implements: blueprint documentation-initialization

    # OpenStack docs suggest 'git commit -a' but be careful
    #   safer bet is to commit the file and then use 'git status' to check
    git commit <file>

    # If it's a change to prior commit use 'git commit --amend'
    #   and don't edit the changeID

    # Check your changes are as you intend
    git show

    # Check it in
    git review

    # Go back to the master branch
    git checkout master

.. _reStructuredText: http://docutils.sourceforge.net/rst.html

