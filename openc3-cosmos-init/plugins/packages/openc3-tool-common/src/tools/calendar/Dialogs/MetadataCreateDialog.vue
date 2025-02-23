<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addstopums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<!-- TODO: COmbine with MetadataUpdateDialog -->
<template>
  <div>
    <v-dialog persistent v-model="show" width="600">
      <v-card>
        <form @submit.prevent="createMetadata">
          <v-system-bar>
            <v-spacer />
            <span>Create Metadata</span>
            <v-spacer />
            <v-tooltip top>
              <template v-slot:activator="{ on, attrs }">
                <div v-on="on" v-bind="attrs">
                  <v-icon data-test="close-metadata-icon" @click="show = !show">
                    mdi-close-box
                  </v-icon>
                </div>
              </template>
              <span>Close</span>
            </v-tooltip>
          </v-system-bar>
          <v-stepper v-model="dialogStep" vertical non-linear>
            <v-stepper-step editable step="1">
              Input start time
            </v-stepper-step>
            <v-stepper-content step="1">
              <v-card-text>
                <div class="pa-2">
                  <color-select-form v-model="color" />
                  <v-row dense>
                    <v-checkbox
                      v-model="userProvidedTime"
                      label="Input Metadata Time"
                    />
                  </v-row>
                  <div v-show="userProvidedTime">
                    <v-row dense>
                      <v-text-field
                        v-model="startDate"
                        type="date"
                        label="Start Date"
                        class="mx-1"
                        :rules="[rules.required]"
                        data-test="metadata-start-date"
                      />
                      <v-text-field
                        v-model="startTime"
                        type="time"
                        step="1"
                        label="Start Time"
                        class="mx-1"
                        :rules="[rules.required]"
                        data-test="metadata-start-time"
                      />
                    </v-row>
                    <v-row class="mx-2 mb-2">
                      <v-radio-group
                        v-model="utcOrLocal"
                        row
                        hide-details
                        class="mt-0"
                      >
                        <v-radio
                          label="LST"
                          value="loc"
                          data-test="lst-radio"
                        />
                        <v-radio
                          label="UTC"
                          value="utc"
                          data-test="utc-radio"
                        />
                      </v-radio-group>
                    </v-row>
                  </div>
                  <v-row>
                    <span
                      class="ma-2 red--text"
                      v-show="timeError"
                      v-text="timeError"
                    />
                  </v-row>
                  <v-row class="mt-2">
                    <v-spacer />
                    <v-btn
                      @click="dialogStep = 2"
                      data-test="create-metadata-step-two-btn"
                      color="success"
                      :disabled="!!timeError"
                    >
                      Continue
                    </v-btn>
                  </v-row>
                </div>
              </v-card-text>
            </v-stepper-content>
            <v-stepper-step editable step="2">Metadata Input</v-stepper-step>
            <v-stepper-content step="2">
              <v-card-text>
                <div class="pa-2">
                  <div style="min-height: 200px">
                    <metadata-input-form v-model="metadata" />
                  </div>
                  <v-row v-show="typeError">
                    <span class="ma-2 red--text" v-text="typeError" />
                  </v-row>
                  <v-row class="mt-2">
                    <v-spacer />
                    <v-btn
                      @click="show = !show"
                      outlined
                      class="mx-2"
                      data-test="create-metadata-cancel-btn"
                    >
                      Cancel
                    </v-btn>
                    <v-btn
                      @click.prevent="createMetadata"
                      class="mx-2"
                      color="primary"
                      type="submit"
                      data-test="create-metadata-submit-btn"
                      :disabled="!!timeError || !!typeError"
                    >
                      Ok
                    </v-btn>
                  </v-row>
                </div>
              </v-card-text>
            </v-stepper-content>
          </v-stepper>
        </form>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import Api from '@openc3/tool-common/src/services/api'
import CreateDialog from '@openc3/tool-common/src/tools/calendar/Dialogs/CreateDialog.js'
import TimeFilters from '@openc3/tool-common/src/tools/calendar/Filters/timeFilters.js'
import ColorSelectForm from '@openc3/tool-common/src/tools/calendar/Forms/ColorSelectForm'
import MetadataInputForm from '@openc3/tool-common/src/tools/calendar/Forms/MetadataInputForm'

export default {
  components: {
    ColorSelectForm,
    MetadataInputForm,
  },
  props: {
    value: Boolean, // value is the default prop when using v-model
  },
  mixins: [CreateDialog, TimeFilters],
  data() {
    return {
      scope: window.openc3Scope,
      dialogStep: 1,
      userProvidedTime: false,
      color: '#003784',
      metadata: [],
      rules: {
        required: (value) => !!value || 'Required',
      },
    }
  },
  watch: {
    show: function () {
      this.updateValues()
    },
  },
  mounted: function () {
    if (this.date !== undefined && this.time !== undefined) {
      this.userProvidedTime = true
    }
  },
  computed: {
    timeError: function () {
      if (!this.color) {
        return 'A color is required.'
      }
      if (!this.userProvidedTime) {
        return null
      }
      const now = new Date()
      const start = Date.parse(`${this.startDate}T${this.startTime}`)
      if (now < start) {
        return 'Invalid start time. Can not be in the future'
      }
      return null
    },
    typeError: function () {
      if (this.metadata.length < 1) {
        return 'Please enter a value in the metadata table.'
      }
      const emptyKeyValue = this.metadata.find(
        (meta) => meta.key === '' || meta.value === ''
      )
      if (emptyKeyValue) {
        return 'Missing or empty key, value in the metadata table.'
      }
      return null
    },
    show: {
      get() {
        return this.value
      },
      set(value) {
        this.$emit('input', value) // input is the default event when using v-model
      },
    },
  },
  methods: {
    updateValues: function () {
      this.dialogStep = 1
      this.calcStartDateTime()
      this.metadata = []
      this.color = '#003784'
    },
    createMetadata: function () {
      const color = this.color
      const metadata = this.metadata.reduce((result, element) => {
        result[element.key] = element.value
        return result
      }, {})
      const data = { color, metadata }
      if (this.userProvidedTime) {
        data.start = this.toIsoString(
          Date.parse(`${this.startDate}T${this.startTime}`)
        )
      }
      Api.post('/openc3-api/metadata', {
        data,
      }).then((response) => {
        this.$notify.normal({
          title: 'Created new Metadata',
          body: `Metadata: (${response.data.start})`,
        })
        this.$emit('update', response.data)
      })
      this.show = !this.show
      this.updateValues()
    },
  },
}
</script>

<style scoped>
.v-stepper--vertical .v-stepper__content {
  width: auto;
  margin: 0px 0px 0px 36px;
  padding: 0px;
}
</style>
