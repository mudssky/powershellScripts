@{
	Severity     = @('Error', 'Warning')
	# IncludeRules = 'PSAvoid*'
	ExcludeRules = @('PSAvoidUsingInvokeExpression',
	 'PSAvoidUsingWriteHost', 
	 'PSUseBOMForUnicodeEncodedFile', 
	 'PSReviewUnusedParameter',
		# 清单中使用*字符比较方便，所以这个提示去掉
	 'PSUseToExportFieldsInManifest'
		#  因为它是仅通过动词来判断针对系统的改动的，所以不靠谱。
	 'PSUseShouldProcessForStateChangingF'
	)
}