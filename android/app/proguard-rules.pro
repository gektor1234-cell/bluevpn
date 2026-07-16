# SnakeYAML checks these desktop JVM introspection types reflectively. Android
# does not provide them, and Green VPN does not use that introspection path.
-dontwarn java.beans.BeanInfo
-dontwarn java.beans.FeatureDescriptor
-dontwarn java.beans.IntrospectionException
-dontwarn java.beans.Introspector
-dontwarn java.beans.PropertyDescriptor

# Release verification reads these compile-time transport flags from DEX.
-keep class pro.greenvpn.app.BuildConfig { *; }
