<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <top-bar :title="title" :menus="menus" />
    <v-container>
      <v-row class="pt-1">
        <v-select
          class="pa-0 mr-2"
          label="Select Target"
          :items="Object.keys(screens).sort()"
          item-text="label"
          item-value="value"
          v-model="selectedTarget"
          @change="targetSelect"
        />
        <v-select
          class="pa-0 mr-3"
          label="Select Screen"
          :items="screens[selectedTarget]"
          v-model="selectedScreen"
          @change="screenSelect"
        />
        <v-btn
          class="primary mr-2"
          :disabled="!selectedScreen"
          @click="() => showScreen(selectedTarget, selectedScreen)"
          data-test="show-screen"
        >
          Show
        </v-btn>
        <v-btn
          class="primary"
          @click="() => newScreen(selectedTarget)"
          data-test="new-screen"
        >
          New Screen
          <v-icon> mdi-file-plus</v-icon>
        </v-btn>
      </v-row>
    </v-container>
    <div class="grid">
      <div
        class="item"
        v-for="def in definitions"
        :key="def.id"
        :id="screenId(def.id)"
        ref="gridItem"
      >
        <div class="item-content">
          <openc3-screen
            :target="def.target"
            :screen="def.screen"
            :definition="def.definition"
            :keywords="keywords"
            :initialFloated="def.floated"
            :initialTop="def.top"
            :initialLeft="def.left"
            :initialZ="def.zIndex"
            @close-screen="closeScreen(def.id)"
            @min-max-screen="refreshLayout"
            @add-new-screen="($event) => showScreen(...$event)"
            @delete-screen="deleteScreen(def)"
            @float-screen="floatScreen(def, ...$event)"
            @unfloat-screen="unfloatScreen(def, ...$event)"
            @drag-screen="dragScreen(def, ...$event)"
            @edit-screen="refreshLayout"
          />
        </div>
      </div>
    </div>
    <!-- Dialogs for opening and saving configs -->
    <open-config-dialog
      v-if="openConfig"
      v-model="openConfig"
      :tool="toolName"
      @success="openConfiguration($event)"
    />
    <save-config-dialog
      v-if="saveConfig"
      v-model="saveConfig"
      :tool="toolName"
      @success="saveConfiguration($event)"
    />
    <new-screen-dialog
      v-if="newScreenDialog"
      v-model="newScreenDialog"
      :target="selectedTarget"
      :screens="screens"
      @success="saveNewScreen"
    />
  </div>
</template>

<script>
import Api from '@openc3/tool-common/src/services/api'
import { OpenC3Api } from '@openc3/tool-common/src/services/openc3-api'
import TopBar from '@openc3/tool-common/src/components/TopBar'
import Openc3Screen from '@openc3/tool-common/src/components/Openc3Screen'
import NewScreenDialog from './NewScreenDialog'
import OpenConfigDialog from '@openc3/tool-common/src/components/OpenConfigDialog'
import SaveConfigDialog from '@openc3/tool-common/src/components/SaveConfigDialog'
import Muuri from 'muuri'

export default {
  components: {
    TopBar,
    Openc3Screen,
    NewScreenDialog,
    OpenConfigDialog,
    SaveConfigDialog,
  },
  data() {
    return {
      title: 'COSMOS Telemetry Viewer',
      counter: 0,
      definitions: [],
      screens: {},
      selectedTarget: '',
      selectedScreen: '',
      newScreenDialog: false,
      grid: null,
      api: null,
      keywords: [],
      menus: [
        {
          label: 'File',
          items: [
            {
              label: 'Open Configuration',
              icon: 'mdi-folder-open',
              command: () => {
                this.openConfig = true
              },
            },
            {
              label: 'Save Configuration',
              icon: 'mdi-content-save',
              command: () => {
                this.saveConfig = true
              },
            },
          ],
        },
      ],
      toolName: 'tlm-viewer',
      openConfig: false,
      saveConfig: false,
    }
  },
  created() {
    // Ensure Offline Access Is Setup For the Current User
    this.api = new OpenC3Api()
    this.api.ensure_offline_access()
    Api.get('/openc3-api/screens').then((response) => {
      response.data.forEach((filename) => {
        let parts = filename.split('/')
        if (this.screens[parts[0]] === undefined) {
          // Must call this.$set to allow Vue to make the screen arrays reactive
          this.$set(this.screens, parts[0], [])
        }
        this.screens[parts[0]].push(parts[2].split('.')[0].toUpperCase())
      })
      if (!this.selectedTarget) {
        this.selectedTarget = Object.keys(this.screens)[0]
      }
    })
    Api.get('/openc3-api/autocomplete/keywords/screen').then((response) => {
      this.keywords = response.data
    })
  },
  mounted() {
    this.grid = new Muuri('.grid', {
      dragEnabled: true,
      // Only allow drags starting from the v-system-bar title
      dragHandle: '.v-system-bar',
    })
    this.grid.on('dragEnd', this.refreshLayout)
  },
  methods: {
    targetSelect(target) {
      this.selectedTarget = target
      this.selectedScreen = ''
    },
    screenSelect(screen) {
      this.selectedScreen = screen
      this.showScreen(this.selectedTarget, this.selectedScreen)
    },
    newScreen() {
      this.newScreenDialog = true
    },
    async saveNewScreen(screenName, packetName, targetName) {
      let text = 'SCREEN AUTO AUTO 1.0\n'
      if (packetName && packetName !== 'BLANK') {
        text += '\nVERTICAL\n'
        await this.api.get_telemetry(targetName, packetName).then((packet) => {
          packet.items.forEach((item) => {
            text += `  LABELVALUE ${targetName} ${packetName} ${item.name}\n`
          })
          text += 'END\n'
        })
      } else {
        text += '\nLABEL NEW\n'
      }
      Api.post('/openc3-api/screen/', {
        data: {
          scope: window.openc3Scope,
          target: targetName,
          screen: screenName,
          text: text,
        },
      }).then((response) => {
        this.newScreenDialog = false
        if (this.screens[targetName] === undefined) {
          // Must call this.$set to allow Vue to make the screen arrays reactive
          this.$set(this.screens, targetName, [])
        }
        this.screens[targetName].push(screenName)
        this.screens[targetName].sort()
        this.selectedTarget = targetName
        this.selectedScreen = screenName
        this.showScreen(targetName, screenName)
      })
    },
    showScreen(target, screen) {
      const def = this.definitions.find(
        (def) => def.target == target && def.screen == screen
      )
      if (!def) {
        this.loadScreen(target, screen).then((response) => {
          this.pushScreen({
            id: this.counter++,
            target: target,
            screen: screen,
            definition: response.data,
            floated: false,
            top: 0,
            left: 0,
            zIndex: 0,
          })
        })
      }
    },
    loadScreen(target, screen) {
      return Api.get('/openc3-api/screen/' + target + '/' + screen, {
        headers: {
          Accept: 'text/plain',
        },
      })
    },
    pushScreen(definition) {
      this.definitions.push(definition)
      this.$nextTick(function () {
        if (!definition.floated) {
          var items = this.grid.add(
            this.$refs.gridItem[this.$refs.gridItem.length - 1],
            {
              active: false,
            }
          )
          this.grid.show(items)
          this.grid.refreshItems().layout()
        }
      })
    },
    closeScreenByName(target, screen) {
      const def = this.definitions.find(
        (def) => def.target == target && def.screen == screen
      )
      if (def) {
        this.closeScreen(def.id)
      }
    },
    closeAll() {
      for (const def of this.definitions) {
        this.closeScreen(def.id)
      }
    },
    closeScreen(id) {
      var items = this.grid.getItems([
        document.getElementById(this.screenId(id)),
      ])
      this.grid.remove(items)
      this.grid.refreshItems().layout()
      this.definitions = this.definitions.filter((value, index, arr) => {
        return value.id != id
      })
    },
    deleteScreen(def) {
      this.closeScreen(def.id)
      var index = this.screens[def.target].indexOf(def.screen)
      if (index !== -1) {
        this.screens[def.target].splice(index, 1)
        if (this.screens[def.target].length === 0) {
          // Must call this.$delete to notify Vue of property deletion
          this.$delete(this.screens, def.target)
        }
      }
    },
    floatScreen(definition, floated, top, left, zIndex) {
      definition.floated = floated
      definition.top = top
      definition.left = left
      definition.zIndex = zIndex
      var items = this.grid.getItems([
        document.getElementById(this.screenId(definition.id)),
      ])
      this.grid.remove(items)
      this.grid.refreshItems().layout()
    },
    unfloatScreen(definition, floated, top, left, zIndex) {
      definition.floated = floated
      definition.top = top
      definition.left = left
      definition.zIndex = zIndex
      var items = [document.getElementById(this.screenId(definition.id))]
      this.grid.add(items)
      this.grid.refreshItems().layout()
    },
    dragScreen(definition, floated, top, left, zIndex) {
      definition.floated = floated
      definition.top = top
      definition.left = left
      definition.zIndex = zIndex
    },
    refreshLayout() {
      setTimeout(() => {
        this.grid.refreshItems().layout()
      }, 600) // TODO: Is 600ms ok for all screens?
    },
    screenId(id) {
      return 'tlmViewerScreen' + id
    },
    openConfiguration: async function (name) {
      this.counter = 0
      this.definitions = []
      let configResponse = await this.api.load_config(this.toolName, name)
      if (configResponse) {
        const config = JSON.parse(configResponse)
        // Load all the screen definitions from the API at once
        const loadScreenPromises = config.map((definition) => {
          return this.loadScreen(definition.target, definition.screen)
        })
        // Wait until they're all loaded
        Promise.all(loadScreenPromises)
          .then((responses) => {
            // Then add all the screens in order
            config.forEach((definition, index) => {
              const response = responses[index]
              setTimeout(() => {
                let floated = definition.floated
                if (!floated) {
                  floated = false
                }
                let top = definition.top || 0
                let left = definition.left || 0
                let zIndex = definition.zIndex || 0
                this.pushScreen({
                  id: this.counter++,
                  target: definition.target,
                  screen: definition.screen,
                  definition: response.data,
                  floated: floated,
                  top: top,
                  left: left,
                  zIndex: zIndex,
                })
              }, 0) // I don't even know... but Muuri complains if this isn't in a setTimeout
            })
          })
          .then(() => {
            setTimeout(this.refreshLayout, 0) // Muuri probably stacked some, so refresh that
          })
      }
    },
    saveConfiguration: function (name) {
      const gridItems = this.grid.getItems().map((item) => item.getElement().id) // TODO: this order isn't reliable for some reason
      const config = this.definitions
        .sort((a, b) => {
          // Sort by their current position on the page
          return gridItems.indexOf(this.screenId(a)) >
            gridItems.indexOf(this.screenId(b))
            ? -1
            : 1
        })
        .map((def) => {
          return {
            screen: def.screen,
            target: def.target,
            floated: def.floated,
            top: def.top,
            left: def.left,
            zIndex: def.zIndex,
          }
        })
      this.api.save_config(this.toolName, name, JSON.stringify(config))
    },
  },
}
</script>

<style scoped>
.grid {
  position: relative;
}
.item {
  position: absolute;
  display: block;
  margin: 5px;
  z-index: 1;
}
.item.muuri-item-dragging {
  z-index: 3;
}
.item.muuri-item-releasing {
  z-index: 2;
}
.item.muuri-item-hidden {
  z-index: 0;
}
.item-content {
  position: relative;
  cursor: pointer;
  border-radius: 6px;
}
</style>
