struct BatchEntry {
    var labels: LokiLabels
    var logEntries: [LokiLog]
	
	  init(labels: LokiLabels, logEntries: [LokiLog]) {
		    self.labels = labels
		    self.logEntries = logEntries
	  }
}
