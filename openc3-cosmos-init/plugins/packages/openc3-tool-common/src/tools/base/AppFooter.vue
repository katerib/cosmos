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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-footer id="footer" app color="tertiary darken-3" height="33">
    <img :src="icon" alt="OpenC3" />
    <span class="footer-text" style="margin-left: 5px">
      OpenC3 {{ edition }} {{ openc3Version }} &copy; 2023 - License:
      {{ license }}
    </span>
    <v-spacer />
    <a :href="sourceUrl" class="white--text text-decoration-underline">
      Source
    </a>
    <v-spacer />
    <div class="justify-right"><clock-footer /></div>
  </v-footer>
</template>

<script>
import ClockFooter from './components/ClockFooter.vue'
import { OpenC3Api } from '../../services/openc3-api'
import icon from '../../../public/img/icon.png'

export default {
  components: {
    ClockFooter,
  },
  props: {
    edition: {
      type: String,
      default: '',
    },
    license: {
      type: String,
      default: '',
    },
  },
  data() {
    return {
      icon: icon,
      sourceUrl: '',
      openc3Version: '',
    }
  },
  created: function () {
    this.getSourceUrl()
  },
  methods: {
    getSourceUrl: function () {
      new OpenC3Api()
        .get_settings(['source_url', 'version'])
        .then((response) => {
          this.sourceUrl = response[0]
          this.openc3Version = `(${response[1]})`
        })
        .catch(() => {
          this.openc3Version = 'Unknown'
        })
    },
  },
}
</script>

<style scoped>
#footer {
  z-index: 1000; /* On TOP! */
}
</style>
