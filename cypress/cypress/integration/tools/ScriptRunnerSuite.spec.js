/*
# Copyright 2021 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This program may also be used under the terms of a commercial or
# enterprise edition license of COSMOS if purchased from the
# copyright holder
*/

describe('ScriptRunner Suite', () => {
  function saveAs(filename) {
    // Save as a suite so we get the suite controls
    cy.get('.v-toolbar').contains('File').click()
    cy.contains('Save As...').click()
    cy.get('.v-dialog:visible').within(() => {
      cy.contains('File Save As')
      cy.contains('INST')
        .parentsUntil('button')
        .eq(0)
        .parent()
        .find('button')
        .click()
      cy.contains('procedures').click()
      cy.get('[data-test=filename]').type('/' + filename)
      cy.contains('Ok').click()
      if (cy.contains('Click OK to overwrite.')) {
        cy.contains('Ok').click()
      }
    })
  }
  function deleteFile() {
    cy.get('.v-toolbar').contains('File').click()
    cy.contains('Delete').click()
    cy.get('.v-dialog:visible').within(() => {
      cy.contains('Ok').click()
    })
  }
  function checkRunningButtons() {
    // After script starts the Script Start/Go and all Suite buttons should be disabled
    cy.get('[data-test=start-go-button]').contains('Go')
    cy.get('[data-test=start-go-button]').should('be.disabled')
    cy.get('[data-test=start-suite]').should('be.disabled')
    cy.get('[data-test=start-group]').should('be.disabled')
    cy.get('[data-test=start-script]').should('be.disabled')
    cy.get('[data-test=setup-suite]').should('be.disabled')
    cy.get('[data-test=setup-group]').should('be.disabled')
    cy.get('[data-test=teardown-suite]').should('be.disabled')
    cy.get('[data-test=teardown-group]').should('be.disabled')
  }

  it('loads Suite controls when opening a suite', () => {
    cy.visit('/tools/scriptrunner')
    // Open the file
    cy.get('.v-toolbar').contains('File').click()
    cy.contains('Open').click()
    cy.get('.v-dialog:visible').within(() => {
      cy.wait(1000) // allow the dialog to open
      cy.contains('Ok').click()
      cy.contains('Nothing selected')
      cy.get('[data-test=search]').type('script_suite')
      cy.contains('script_suite').click()
      cy.contains('Ok').click()
    })
    // Verify filename
    cy.get('[data-test=filename]')
      .invoke('val')
      .should('include', 'script_suite')
    // Verify defaults in the Suite options
    cy.get('[data-test=pause-on-error]').should('be.checked')
    cy.get('[data-test=manual]').should('be.checked')
    cy.get('[data-test=continue-after-error]').should('be.checked')
    cy.get('[data-test=loop]').should('not.be.checked')
    cy.get('[data-test=abort-after-error]').should('not.be.checked')
    cy.get('[data-test=break-loop-on-error]').should('be.disabled')
    // Verify the drop downs are populated
    cy.get('[data-test=select-suite]').parent().parent().contains('MySuite')
    cy.get('[data-test=select-group]')
      .parent()
      .parent()
      .contains('ExampleGroup')
    cy.get('[data-test=select-script]').parent().parent().contains('script')
    // Verify Suite Start buttons are enabled
    cy.get('[data-test=start-suite]').should('be.enabled')
    cy.get('[data-test=start-group]').should('be.enabled')
    cy.get('[data-test=start-script]').should('be.enabled')
    // Verify Script Start button is disabled
    cy.get('[data-test=start-go-button]').should('be.disabled')
  })

  it('starts a suite', () => {
    cy.visit('/tools/scriptrunner')
    cy.get('#editor').type('load "cosmos/script/suite.rb"\n')
    cy.get('#editor').type('class TestGroup < Cosmos::Group\n')
    cy.get('#editor').type('def test_test; puts "test"; end\n')
    cy.get('#editor').type('{backspace}end\n')
    cy.get('#editor').type('class TestSuite < Cosmos::Suite\n')
    cy.get('#editor').type('def setup; Cosmos::Group.puts("setup"); end\n')
    cy.get('#editor').type(
      '{backspace}def teardown; Cosmos::Group.puts("teardown"); end\n'
    )
    cy.get('#editor').type(
      '{backspace}def initialize\nsuper()\nadd_group("TestGroup")\nend\nend\n'
    )
    saveAs('test_suite1.rb')

    // Verify the suite startup, teardown buttons are enabled
    cy.get('[data-test=setup-suite]').should('be.enabled')
    cy.get('[data-test=teardown-suite]').should('be.enabled')

    // Run suite setup
    cy.get('[data-test=setup-suite]').click({ force: true })
    // Wait for the results
    cy.get('.v-dialog:visible', { timeout: 20000 }).within(() => {
      cy.contains('Script Results')
      cy.get('textarea')
        .invoke('val')
        .should('include', 'setup:PASS')
        .should('include', 'Total Tests : 1')
        .should('include', 'Pass : 1')
      cy.contains('Ok').click()
    })

    // Run suite teardown
    cy.get('[data-test=teardown-suite]').click({ force: true })
    // Wait for the results
    cy.get('.v-dialog:visible', { timeout: 20000 }).within(() => {
      cy.contains('Script Results')
      cy.get('textarea')
        .invoke('val')
        .should('include', 'teardown:PASS')
        .should('include', 'Total Tests : 1')
        .should('include', 'Pass : 1')
      cy.contains('Ok').click()
    })

    // Start the suite
    cy.get('[data-test=start-suite]').click({ force: true })
    checkRunningButtons()

    // Wait for the results
    cy.get('.v-dialog:visible', { timeout: 20000 }).within(() => {
      cy.contains('Script Results')
      cy.get('textarea')
        .invoke('val')
        .should('include', 'setup:PASS')
        .should('include', 'teardown:PASS')
        .should('include', 'Total Tests : 3')
        .should('include', 'Pass : 3')
      cy.contains('Ok').click()
    })

    // Rewrite the script but remove setup and teardown
    cy.get('#editor').type('{ctrl}a{del}')
    cy.wait(500)
    cy.get('#editor').type('load "cosmos/script/suite.rb"\n')
    cy.get('#editor').type('class TestGroup < Cosmos::Group\n')
    cy.get('#editor').type('def test_test; puts "test"; end\n')
    cy.get('#editor').type('{backspace}end\n')
    cy.get('#editor').type('class TestSuite < Cosmos::Suite\n')
    cy.get('#editor').type(
      '{backspace}def initialize\nsuper()\nadd_group("TestGroup")\nend\nend\n'
    )
    // Verify filename is marked as edited
    cy.get('[data-test=filename]').invoke('val').should('include', '*')
    cy.get('#editor').type('{ctrl}s') // Save

    // Verify the suite startup, teardown buttons are disabled
    cy.get('[data-test=setup-suite]').should('be.disabled')
    cy.get('[data-test=teardown-suite]').should('be.disabled')

    deleteFile()
  })

  it('starts a group', () => {
    cy.visit('/tools/scriptrunner')
    cy.wait(500)
    cy.get('#editor').type('load "cosmos/script/suite.rb"\n')
    cy.get('#editor').type('class TestGroup1 < Cosmos::Group\n')
    cy.get('#editor').type('def setup; Cosmos::Group.puts("setup"); end\n')
    cy.get('#editor').type(
      '{backspace}def teardown; Cosmos::Group.puts("teardown"); end\n'
    )
    cy.get('#editor').type('{backspace}def test_test1; puts "test"; end\n')
    cy.get('#editor').type('{backspace}end\n')
    cy.get('#editor').type('class TestGroup2 < Cosmos::Group\n')
    cy.get('#editor').type('def test_test2; puts "test"; end\n')
    cy.get('#editor').type('{backspace}end\n')
    cy.get('#editor').type('class TestSuite < Cosmos::Suite\n')
    cy.get('#editor').type(
      'def initialize\nsuper()\nadd_group("TestGroup1")\nadd_group("TestGroup2")\nend\nend\n'
    )
    saveAs('test_suite2.rb')

    // Verify the group startup, teardown buttons are enabled
    cy.get('[data-test=setup-group]').should('be.enabled')
    cy.get('[data-test=teardown-group]').should('be.enabled')

    // Run group setup
    cy.get('[data-test=setup-group]').click({ force: true })
    // Wait for the results
    cy.get('.v-dialog:visible', { timeout: 20000 }).within(() => {
      cy.contains('Script Results')
      cy.get('textarea')
        .invoke('val')
        .should('include', 'setup:PASS')
        .should('include', 'Total Tests : 1')
        .should('include', 'Pass : 1')
      cy.contains('Ok').click()
    })

    // Run group teardown
    cy.get('[data-test=teardown-group]').click({ force: true })
    // Wait for the results
    cy.get('.v-dialog:visible', { timeout: 20000 }).within(() => {
      cy.contains('Script Results')
      cy.get('textarea')
        .invoke('val')
        .should('include', 'teardown:PASS')
        .should('include', 'Total Tests : 1')
        .should('include', 'Pass : 1')
      cy.contains('Ok').click()
    })

    // Start the group
    cy.get('[data-test=start-group]').click({ force: true })
    checkRunningButtons()

    // Wait for the results
    cy.get('.v-dialog:visible', { timeout: 20000 }).within(() => {
      cy.contains('Script Results')
      cy.get('textarea')
        .invoke('val')
        .should('include', 'TestGroup1')
        .should('not.include', 'TestGroup2')
        .should('include', 'Total Tests : 3')
        .should('include', 'Pass : 3')
      cy.contains('Ok').click()
    })

    // Rewrite the script but remove setup and teardown
    cy.get('#editor').type('{ctrl}a{del}')
    cy.wait(500)
    cy.get('#editor').type('load "cosmos/script/suite.rb"\n')
    cy.get('#editor').type('class TestGroup1 < Cosmos::Group\n')
    cy.get('#editor').type('def test_test1; puts "test"; end\n')
    cy.get('#editor').type('{backspace}end\n')
    cy.get('#editor').type('class TestGroup2 < Cosmos::Group\n')
    cy.get('#editor').type('def test_test2; puts "test"; end\n')
    cy.get('#editor').type('{backspace}end\n')
    cy.get('#editor').type('class TestSuite < Cosmos::Suite\n')
    cy.get('#editor').type(
      'def initialize\nsuper()\nadd_group("TestGroup1")\nadd_group("TestGroup2")\nend\nend\n'
    )
    // Verify filename is marked as edited
    cy.get('[data-test=filename]').invoke('val').should('include', '*')
    cy.get('#editor').type('{ctrl}s') // Save

    // Verify the group startup, teardown buttons are disabled
    cy.get('[data-test=setup-group]').should('be.disabled')
    cy.get('[data-test=teardown-group]').should('be.disabled')

    deleteFile()
  })

  it('starts a script', () => {
    cy.visit('/tools/scriptrunner')
    cy.get('#editor').type('load "cosmos/script/suite.rb"\n')
    cy.get('#editor').type('class TestGroup < Cosmos::Group\n')
    cy.get('#editor').type('def test_test1; Cosmos::Group.puts "test1"; end\n')
    cy.get('#editor').type('def test_test2; Cosmos::Group.puts "test2"; end\n')
    cy.get('#editor').type('{backspace}end\n')
    cy.get('#editor').type('class TestSuite < Cosmos::Suite\n')
    cy.get('#editor').type(
      'def initialize; super(); add_group("TestGroup"); end\n'
    )
    cy.get('#editor').type('{backspace}end\n')
    saveAs('test_suite3.rb')

    // Start the script
    cy.get('[data-test=start-script]').click({ force: true })
    checkRunningButtons()

    // Wait for the results
    cy.get('.v-dialog:visible', { timeout: 20000 }).within(() => {
      cy.contains('Script Results')
      cy.get('textarea')
        .invoke('val')
        .should('include', 'test1')
        .and('include', 'Total Tests : 1')
        .and('include', 'Pass : 1')
      cy.contains('Ok').click()
    })

    deleteFile()
  })

  it('handles manual mode', () => {
    cy.get('#editor').type('load "cosmos/script/suite.rb"\n')
    cy.get('#editor').type('class TestGroup < Cosmos::Group\n')
    cy.get('#editor').type(
      'def test_test1; Cosmos::Group.puts "manual1" if $manual; end\n'
    )
    cy.get('#editor').type(
      'def test_test2; Cosmos::Group.puts "manual2" unless $manual; end\n'
    )
    cy.get('#editor').type('{backspace}end\n')
    cy.get('#editor').type('class TestSuite < Cosmos::Suite\n')
    cy.get('#editor').type(
      'def initialize; super(); add_group("TestGroup"); end\n'
    )
    cy.get('#editor').type('{backspace}end\n')
    saveAs('test_suite4.rb')

    // Start the group
    cy.get('[data-test=start-group]').click({ force: true })
    checkRunningButtons()

    // Wait for the results
    cy.get('.v-dialog:visible', { timeout: 20000 }).within(() => {
      cy.contains('Script Results')
      cy.get('textarea')
        .invoke('val')
        .and('include', 'Manual = true')
        .and('include', 'manual1')
        .and('not.include', 'manual2')
        .and('include', 'Total Tests : 2')
        .and('include', 'Pass : 2')
      cy.contains('Download').click()
      cy.contains('Ok').click()
    })

    cy.get('[data-test=manual]').click({ force: true }) // uncheck Manual

    // Start the group
    cy.get('[data-test=start-group]').click({ force: true })
    checkRunningButtons()

    // Wait for the results
    cy.get('.v-dialog:visible', { timeout: 20000 }).within(() => {
      cy.contains('Script Results')
      cy.get('textarea')
        .invoke('val')
        .and('include', 'Manual = false')
        .and('not.include', 'manual1')
        .and('include', 'manual2')
        .and('include', 'Total Tests : 2')
        .and('include', 'Pass : 2')
      cy.contains('Download').click()
      cy.contains('Ok').click()
    })
    deleteFile()
  })
})
