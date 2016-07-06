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

    # create a branch - common branch naming for docs follows the
    #   blueprint name but this is not enforced
    git checkout -b bp/documentation-initialization
    
    # subsequent independent changes are commonly named
    #   bp/documentation-initialization-X
    #   where X is monotomically increasing

    # verify the scope of your changes
    git status

    # ensure that the commit message references the blueprint
    # by adding this line:
    # Partially-implements: blueprint documentation-initialization
    #

    # OpenStack docs suggest 'git commit -a' but be careful
    #   safer bet is to commit the file and then use 'git status' to check
    git commit <file>
    # if it's a change to prior commit use 'git commit --apend'
    #   instead and don't edit the changeID

    # check again
    git status

    # check it in
    git review

    # go back to the master branch
    git checkout master

.. _reStructuredText: http://docutils.sourceforge.net/rst.html

