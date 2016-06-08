=========================
Contributing to Openstack
=========================
.. include:: ../../CONTRIBUTING.rst


================================
Contributing to kolla-kubernetes
================================


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

.. _reStructuredText: http://docutils.sourceforge.net/rst.html


Code Patches
============

Before submitting a code patch, please ensure that your changes will pass the
build server tests.  The build server distribution is Ubuntu Trusty.

::

    # Install Python Header files
    #   Required for building 'netifaces' dependency
    sudo apt-get -y install python-dev python3-all-dev

    # Run only Build Server Tests:
    #   Build server only runs: pep8, py34, py27, (and docs)
    #   py3 tests must run before py2 tests because of bug:
    #   https://bugs.launchpad.net/testrepository/+bug/1229445
    # Code Style Tests
    tox -e pep8-constraints -v
    # Python 3 Tests
    tox -e py34-constraints -v
    # Python 2 Tests
    tox -e py27-constraints -v

    # Run all tests
    tox -v

