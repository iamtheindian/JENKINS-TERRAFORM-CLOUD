<html>
<head>
<title>	MY FIRST WEBPAGE </title>
</head>
<style>
body {
  background-color: #E6E6FA;
}
</style>
<body>
<pre>
<?php
$filepath=`cat /var/www/html/domain_name.txt`; 
echo "<h2>PHP is Fun!</h2>";
echo "Hello world!<br>";
echo "I'm about to learn PHP!<br>";
echo "This ", "image ", "is ", "get ", "by cloudfront disrtibution domain_name<br>";
echo "The Domain name is ${filepath} <br>";
echo "<img src='https://${filepath}/MBM.png' height=100 width=100 />";
?>
</pre>
<p><a href="https://www.linkedin.com/in/rahul-bairwa-6b0552198">Visit My LinkedIn Profile!</a></p>

</body>
</html>