一、合入代码规则
	1、合入代码注释形式：xxx(姓名) add for xxx(功能)
	   另：如果合入代码有问题单，需在注释后添加问题单号：xxx(姓名) add for xxx(功能) #xxx(问题单号)
	
	2、注释必须在合入代码的开头和结尾均添加
	
	3、合入代码后，要在本文件下列地方写下合入代码的注释信息，方便查找

	4、合入代码过程中，禁止删除代码。有不需要的代码，注释(/*....*/)即可

二、现有已合入的特性

1、worm-----------------------------worm属性

2、user log-------------------------用户审计

3、smartlayer-----------------------自动分级

4、userquota------------------------用户配额

5、poolquota------------------------池配额

6、nfs req--------------------------

7、smartdcache----------------------

8、ec-rmw---------------------------直写纠删

9、perform point feature------------osd性能打点

10、accidental mds crash-------------偶发性mds崩溃

11、official bug--------------------同步官方bug

12、mon eliminate 0 err-------------除0导致mon挂掉

13、file attribute synchronous------AB机头同步慢

14、unknown patch-------------------对于不知是何功能的代码注释

15、replication----------------------远程复制

