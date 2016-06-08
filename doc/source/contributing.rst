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

.. _reStructuredText: http://docutils.sourceforge.net/rst.html

