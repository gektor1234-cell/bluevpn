package pro.greenvpn.app

internal object GreenVpnApplicationSelectorPolicy {
    private val selectorPattern = Regex(
        "^\\s*(IncludedApplications|ExcludedApplications)\\s*=\\s*(.*?)\\s*$",
        setOf(RegexOption.IGNORE_CASE),
    )

    fun filterInstalledApplications(
        configText: String,
        isInstalled: (String) -> Boolean,
    ): String {
        val filtered = mutableListOf<String>()
        for (line in configText.split(Regex("\\r?\\n"))) {
            val match = selectorPattern.matchEntire(line)
            if (match == null) {
                filtered.add(line)
                continue
            }

            val fieldName = match.groupValues[1]
            val packages = match.groupValues[2]
                .split(',')
                .map { it.trim() }
                .filter { it.isNotEmpty() && isInstalled(it) }
                .distinct()
                .sorted()
            if (packages.isNotEmpty()) {
                filtered.add("$fieldName = ${packages.joinToString(", ")}")
            } else if (fieldName.equals("IncludedApplications", ignoreCase = true)) {
                throw IllegalArgumentException("No selected Android applications are installed")
            }
        }
        return filtered.joinToString("\n")
    }
}
