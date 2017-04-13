import Vue from 'vue'

import App from './App.vue'

require('./app.css')

window.onload = function () {
  new Vue({
    el: '#app',
    render: h => h(App)
  })
}