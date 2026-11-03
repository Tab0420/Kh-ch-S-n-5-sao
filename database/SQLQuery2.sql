-- BẢN GỘP SQLQUERY2,3,4,5,8,9,10,11 VÀ CẬP NHẬT MỚI.
-- Dùng trên booking_db đã có các bảng gốc và dữ liệu phòng.
-- Không xóa database, đơn đặt phòng hoặc giao dịch.
-- Giá, lịch và sức chứa mẫu được giữ trong dữ liệu cấu hình.

USE booking_db;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

IF @@TRANCOUNT<>0
    THROW 51000,N'Hãy mở New Query không có giao dịch đang dang dở.',1;

BEGIN TRY
BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.Users',N'U') IS NULL
 OR OBJECT_ID(N'dbo.Room_Types',N'U') IS NULL
 OR OBJECT_ID(N'dbo.Rooms',N'U') IS NULL
 OR OBJECT_ID(N'dbo.Bookings',N'U') IS NULL
 OR OBJECT_ID(N'dbo.Booking_Details',N'U') IS NULL
 OR COL_LENGTH(N'dbo.Rooms',N'ten_phong') IS NULL
 THROW 51000,N'Cần database gốc booking_db và tên phòng trước khi chạy bản cập nhật gộp.',1;

DECLARE @lock INT;
EXEC @lock=sys.sp_getapplock
    @Resource='DiningInventory',
    @LockMode='Exclusive',
    @LockOwner='Transaction',
    @LockTimeout=10000;

IF @lock<0
    THROW 51000,N'Có lịch đang được xử lý. Dừng web rồi chạy lại bản cập nhật.',1;

-- =========================================================
-- 1. HỒ SƠ PHÒNG
-- =========================================================

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Room_Profiles'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.Room_Profiles(
  room_id VARCHAR(50) NOT NULL PRIMARY KEY,
  mo_ta NVARCHAR(1200) NOT NULL,
  khong_gian NVARCHAR(1000) NOT NULL,
  phong_tam NVARCHAR(1000) NOT NULL,
  thiet_bi NVARCHAR(1000) NOT NULL,
  tien_ich NVARCHAR(1200) NOT NULL,
  phu_hop NVARCHAR(600) NOT NULL,
  luu_y NVARCHAR(1000) NOT NULL,
  nguon_tham_khao NVARCHAR(1500) NULL,
  la_noi_dung_mau BIT NOT NULL DEFAULT 1,
  cap_nhat_luc DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT FK_Room_Profiles_Rooms FOREIGN KEY(room_id)
   REFERENCES dbo.Rooms(room_id) ON DELETE CASCADE
 );
END;
';

EXEC sys.sp_executesql N'
IF COL_LENGTH(N''dbo.Room_Profiles'',N''diem_noi_bat'') IS NULL
 ALTER TABLE dbo.Room_Profiles ADD diem_noi_bat NVARCHAR(1000) NULL;
IF COL_LENGTH(N''dbo.Room_Profiles'',N''tien_nghi_chung'') IS NULL
 ALTER TABLE dbo.Room_Profiles ADD tien_nghi_chung NVARCHAR(800) NULL;
IF COL_LENGTH(N''dbo.Room_Profiles'',N''phien_ban_noi_dung'') IS NULL
 ALTER TABLE dbo.Room_Profiles ADD phien_ban_noi_dung INT NOT NULL DEFAULT 1;
';

-- Nội dung chung cho phòng chưa có hồ sơ.
EXEC sys.sp_executesql N'
DECLARE @Types TABLE(
 ten_loai NVARCHAR(150),mo_ta NVARCHAR(1200),
 khong_gian NVARCHAR(1000),phong_tam NVARCHAR(1000),
 thiet_bi NVARCHAR(1000),tien_ich NVARCHAR(1200),
 phu_hop NVARCHAR(600),nguon NVARCHAR(1500)
);
INSERT @Types VALUES
(
 N''Phòng Superior'',
 N''Không gian nghỉ ngơi gọn gàng, ưu tiên sự tiện dụng cho chuyến công tác hoặc kỳ nghỉ ngắn.'',
 N''Khu vực ngủ với đèn đọc sách|Bàn làm việc hoặc bàn trang điểm|Tủ quần áo và chỗ để hành lý|Rèm che sáng'',
 N''Phòng tắm riêng có nước nóng|Vòi sen|Máy sấy tóc|Khăn tắm và đồ dùng vệ sinh cơ bản'',
 N''TV màn hình phẳng và kênh truyền hình|Điều hòa điều chỉnh trong phòng|Wi-Fi|Điện thoại nội bộ|Két an toàn|Ấm đun nước'',
 N''Trà và cà phê|Minibar có tính phí|Dọn phòng theo lịch khách sạn'',
 N''Khách công tác|Khách đi một mình|Cặp đôi nghỉ ngắn ngày'',
 N''https://www.navadahotel.com/superior-twin-room-with-city-view-6-23-1-room-single.html''
),
(
 N''Phòng Deluxe'',
 N''Phòng nghỉ có thêm không gian thư giãn, kết hợp khu vực làm việc và các tiện ích phục vụ lưu trú thoải mái.'',
 N''Góc ngồi thư giãn|Bàn làm việc và gương trang điểm|Tủ quần áo, chỗ để hành lý|Rèm che sáng'',
 N''Phòng tắm riêng|Bồn tắm hoặc khu vực tắm đứng theo bố trí phòng|Máy sấy tóc|Khăn tắm, dép và áo choàng'',
 N''TV màn hình phẳng|Điều hòa điều chỉnh trong phòng|Wi-Fi|Két an toàn|Ấm đun nước và bộ tách trà|Minibar'',
 N''Trà, cà phê trong phòng|Bàn ủi theo yêu cầu|Dịch vụ ăn uống tại phòng có tính phí'',
 N''Cặp đôi|Khách công tác cần góc làm việc|Khách lưu trú nhiều ngày'',
 N''https://havanahotel.vn/en/rooms/deluxe-huong-bien''
),
(
 N''Phòng Hướng Biển'',
 N''Không gian nghỉ dưỡng hướng ra biển, có góc ngồi ngắm cảnh và các tiện nghi phục vụ kỳ nghỉ bên bờ biển.'',
 N''Cửa kính đón ánh sáng và hướng nhìn ra biển|Góc ngồi thư giãn cạnh cửa sổ|Ban công theo bố trí phòng|Tủ quần áo và chỗ để hành lý'',
 N''Phòng tắm riêng có nước nóng|Vòi sen và đồ dùng vệ sinh|Máy sấy tóc|Khăn tắm, dép và áo choàng'',
 N''TV màn hình phẳng|Wi-Fi|Điều hòa điều chỉnh trong phòng|Két an toàn|Ấm đun nước|Minibar'',
 N''Trà và cà phê|Bàn ghế thư giãn|Dọn phòng theo lịch khách sạn'',
 N''Cặp đôi nghỉ dưỡng|Khách yêu thích ngắm biển|Khách muốn không gian thư giãn có ánh sáng tự nhiên'',
 N''https://www.navadahotel.com/deluxe-twin-room-with-sea-view-and-with-balcony-11-23-1-room-single.html''
),
(
 N''Phòng Gia Đình'',
 N''Không gian lưu trú cho gia đình hoặc nhóm nhỏ, kết hợp khu vực nghỉ ngơi và góc sinh hoạt chung thuận tiện.'',
 N''Khu vực ngủ cho gia đình theo cấu hình giường đã công bố|Sofa và góc sinh hoạt chung|Bàn ăn nhỏ|Bếp nhỏ và tủ lạnh'',
 N''Phòng tắm riêng|Vòi sen hoặc bồn tắm theo bố trí|Máy sấy tóc|Khăn tắm và đồ dùng vệ sinh'',
 N''TV màn hình phẳng|Wi-Fi|Điều hòa|Két an toàn|Ấm đun nước|Lò vi sóng tại khu bếp'',
 N''Dụng cụ ăn uống cơ bản|Hỗ trợ nôi em bé theo yêu cầu và tình trạng sẵn có|Dọn phòng theo lịch khách sạn'',
 N''Gia đình có trẻ nhỏ|Nhóm bạn trong giới hạn sức chứa|Khách lưu trú dài ngày'',
 N''https://havanahotel.vn/en/rooms/family-suite''
),
(
 N''Phòng Suite'',
 N''Không gian nghỉ dưỡng có khu tiếp khách riêng, phù hợp với khách cần sự riêng tư và tiện nghi thư giãn cao hơn.'',
 N''Khu vực ngủ và phòng khách riêng|Sofa cùng bàn trà|Bàn làm việc|Tủ quần áo và chỗ để hành lý'',
 N''Phòng tắm rộng|Bồn tắm Jacuzzi theo cấu hình phòng|Khu vực vòi sen|Máy sấy tóc, áo choàng và dép'',
 N''TV màn hình phẳng|Wi-Fi|Điều hòa|Két an toàn|Minibar|Bộ pha trà và cà phê'',
 N''Góc tiếp khách riêng|Dịch vụ ăn uống tại phòng có tính phí|Bàn ủi theo yêu cầu|Dọn phòng theo lịch khách sạn'',
 N''Cặp đôi nghỉ dưỡng|Khách công tác cần không gian tiếp khách|Khách ưu tiên sự riêng tư'',
 N''https://havanahotel.vn/en/rooms/junior-suite-king|https://havanahotel.vn/en/rooms/executive-suite''
),
(
 N''Phòng Cao Cấp'',
 N''Không gian nghỉ dưỡng riêng tư lấy cảm hứng từ các villa cao cấp, kết hợp khu sinh hoạt trong nhà và khu thư giãn ngoài trời.'',
 N''Khu vực ngủ theo cấu hình giường đã công bố|Phòng khách với sofa|Bàn ăn và bếp nhỏ|Sân hiên hoặc khu ngồi ngoài trời'',
 N''Phòng tắm riêng|Bồn tắm và khu vực vòi sen|Máy sấy tóc|Áo choàng, dép và đồ dùng vệ sinh'',
 N''TV màn hình phẳng|Wi-Fi|Điều hòa|Két an toàn|Tủ lạnh hoặc minibar|Bộ pha trà và cà phê'',
 N''Hồ bơi riêng theo cấu hình phòng|Khu vực thư giãn ngoài trời|Hỗ trợ quản gia theo lịch phục vụ|Ăn uống riêng có tính phí'',
 N''Gia đình nghỉ dưỡng|Nhóm nhỏ trong giới hạn sức chứa|Khách cần không gian riêng tư'',
 N''https://vinpearl.com/en/hotels/vinpearl-resort-nha-trang''
);

INSERT dbo.Room_Profiles(
 room_id,mo_ta,khong_gian,phong_tam,thiet_bi,
 tien_ich,phu_hop,luu_y,nguon_tham_khao
)
SELECT r.room_id,p.mo_ta,p.khong_gian,p.phong_tam,p.thiet_bi,
 p.tien_ich,p.phu_hop,
 N''Nội dung tiện nghi minh họa, chờ khách sạn xác nhận.|Minibar, ăn uống và các dịch vụ bổ sung có thể tính phí.|Các yêu cầu đặc biệt tùy tình trạng sẵn có.'',
 p.nguon
FROM dbo.Rooms r
JOIN dbo.Room_Types t ON t.type_id=r.type_id
JOIN @Types p ON p.ten_loai=t.ten_loai
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.Room_Profiles x WHERE x.room_id=r.room_id
);
';

-- Nội dung riêng từng phòng, phiên bản 2.
EXEC sys.sp_executesql N'
DECLARE @Data TABLE(
 room_id VARCHAR(50),ten_loai NVARCHAR(150),
 mo_ta NVARCHAR(1200),diem_noi_bat NVARCHAR(1000),
 khong_gian NVARCHAR(1000),phong_tam NVARCHAR(1000),
 thiet_bi NVARCHAR(1000),tien_ich NVARCHAR(1200),
 phu_hop NVARCHAR(600),luu_y NVARCHAR(1000)
);
INSERT @Data VALUES
(
 ''P101'',N''Phòng Superior'',
 N''Không gian gọn gàng hướng đến khách công tác, tập trung vào bàn làm việc và khu cất hành lý thuận tiện.'',
 N''Góc làm việc riêng|Bố trí gọn cho chuyến công tác|Đèn đọc sách cạnh giường'',
 N''Bàn làm việc có ghế tựa|Kệ vali gần lối vào|Tủ quần áo treo đồ|Khu giường ngủ tách khỏi bàn làm việc'',
 N''Bồn tắm nhỏ kết hợp vòi sen|Lavabo và gương soi|Máy sấy tóc gắn tường|Bộ khăn và đồ vệ sinh cơ bản'',
 N''Điện thoại nội bộ|Đèn bàn làm việc|Gương soi toàn thân'',
 N''Chỗ cắm sạc tại bàn|Móc treo áo khoác|Minibar có tính phí'',
 N''Khách công tác ngắn ngày|Khách ưu tiên sự gọn gàng, tiện dụng'',
 N''Bàn ủi được hỗ trợ theo yêu cầu và tình trạng sẵn có.''
),
(
 ''P102'',N''Phòng Superior'',
 N''Phòng nghỉ theo phong cách nhẹ nhàng, chú trọng góc đọc sách và bàn trang điểm cho kỳ nghỉ thư thái.'',
 N''Ghế đọc sách gần cửa sổ|Bàn trang điểm có gương|Phong cách nhẹ nhàng'',
 N''Ghế thư giãn và bàn nhỏ|Bàn trang điểm liền tủ đồ|Khu giường ngủ có rèm che sáng|Ngăn để đồ cá nhân'',
 N''Bồn tắm với vòi sen cầm tay|Kệ mỹ phẩm cạnh lavabo|Gương trang điểm|Máy sấy tóc và khăn tắm'',
 N''Đèn đọc sách đầu giường|Điện thoại nội bộ|Đèn gương trang điểm'',
 N''Góc ngồi uống trà|Rèm che sáng|Móc áo và kệ hành lý'',
 N''Cặp đôi nghỉ ngắn ngày|Khách thích đọc sách và nghỉ ngơi'',
 N''Yêu cầu trang trí dịp đặc biệt cần báo trước với khách sạn.''
),
(
 ''P201'',N''Phòng Deluxe'',
 N''Phòng Deluxe thiên về thư giãn với ghế bành, bàn trà và khu phòng tắm có bồn tắm nằm.'',
 N''Ghế bành và bàn trà|Bồn tắm nằm|Không gian nghỉ dưỡng ấm áp'',
 N''Ghế bành ở góc phòng|Bàn trà cạnh khu ghế|Bàn viết tách khỏi vị trí ngủ|Tủ quần áo và giá vali'',
 N''Bồn tắm nằm kết hợp vòi sen|Mặt bàn lavabo để đồ cá nhân|Gương lớn|Áo choàng, khăn và máy sấy tóc'',
 N''Đèn đứng ở góc ghế bành|Bảng điều khiển cạnh giường|Minibar có tính phí'',
 N''Bộ tách uống trà tại bàn|Dép đi trong phòng|Hỗ trợ ăn uống tại phòng có tính phí'',
 N''Cặp đôi thích nghỉ dưỡng trong phòng|Khách muốn có góc ngồi riêng'',
 N''Dịch vụ ăn uống tại phòng được tính riêng theo thực đơn.''
),
(
 ''P202'',N''Phòng Deluxe'',
 N''Phòng Deluxe ưu tiên ánh sáng tự nhiên, bàn làm việc cạnh cửa sổ và phòng tắm đứng gọn, hiện đại.'',
 N''Bàn làm việc cạnh cửa sổ|Buồng tắm kính|Góc ghế đọc sách'',
 N''Bàn viết hướng ra cửa sổ|Ghế đọc sách có đèn|Bàn trang điểm và gương|Tủ đồ có ngăn hành lý'',
 N''Buồng tắm đứng có vách kính|Vòi sen trên cao|Kệ khăn riêng|Lavabo, gương và máy sấy tóc'',
 N''Đèn chiếu sáng tại bàn viết|Điện thoại nội bộ|Minibar có tính phí'',
 N''Rèm che sáng hai lớp|Góc uống trà cạnh cửa sổ|Hỗ trợ bàn ủi theo yêu cầu'',
 N''Khách công tác kết hợp nghỉ dưỡng|Khách thích không gian có ánh sáng tự nhiên'',
 N''Bàn ủi được phục vụ theo yêu cầu và tình trạng sẵn có.''
),
(
 ''P301'',N''Phòng Hướng Biển'',
 N''Phòng nghỉ tập trung vào trải nghiệm ngắm biển với ban công, bàn ghế ngoài trời và góc ngủ hướng về cửa kính.'',
 N''Ban công ngắm biển|Bàn ghế ngoài trời|Góc nghỉ hướng ra cửa kính'',
 N''Khu giường ngủ nhìn về phía cửa kính|Bàn ghế tại ban công|Lối ra ban công từ phòng ngủ|Tủ đồ và kệ hành lý trong nhà'',
 N''Bồn tắm kết hợp vòi sen|Lavabo và gương lớn|Giá treo khăn gần cửa tắm|Máy sấy tóc'',
 N''Đèn đọc sách tại giường|Điện thoại nội bộ|Minibar có tính phí'',
 N''Góc ngồi ngắm cảnh ngoài trời|Rèm che nắng|Dép đi trong phòng'',
 N''Khách yêu thích ban công và cảnh biển|Cặp đôi nghỉ dưỡng ven biển'',
 N''Cần đóng cửa ban công khi dùng điều hòa; việc sử dụng ban công phụ thuộc điều kiện thời tiết.''
),
(
 ''P302'',N''Phòng Hướng Biển'',
 N''Phòng hướng biển chú trọng góc nhìn qua cửa kính lớn, có chỗ đọc sách và bàn làm việc trong nhà.'',
 N''Cửa kính lớn nhìn ra biển|Ghế thư giãn trong nhà|Góc làm việc có ánh sáng tự nhiên'',
 N''Ghế dài cạnh cửa kính|Bàn làm việc tách khỏi khu ngủ|Bàn trang điểm|Tủ đồ và ngăn cất hành lý'',
 N''Bồn tắm và khu vực vòi sen|Kệ đặt đồ vệ sinh|Gương trang điểm|Áo choàng, khăn và máy sấy tóc'',
 N''Đèn tại góc đọc sách|Điện thoại nội bộ|Minibar có tính phí'',
 N''Góc uống trà có tầm nhìn ra biển|Rèm che sáng|Hỗ trợ bàn ủi theo yêu cầu'',
 N''Khách muốn ngắm biển trong không gian kín|Khách làm việc từ xa trong kỳ nghỉ'',
 N''Các yêu cầu phòng yên tĩnh cần báo trước và phụ thuộc tình trạng sẵn có.''
),
(
 ''P401'',N''Phòng Gia Đình'',
 N''Phòng gia đình chú trọng sinh hoạt hằng ngày, có góc ăn uống và khu bếp để chuẩn bị bữa ăn đơn giản.'',
 N''Bếp nhỏ và bàn ăn gia đình|Tủ lạnh, lò vi sóng|Góc sinh hoạt chung'',
 N''Khu ngủ theo cấu hình giường đã công bố|Bàn ăn và ghế|Góc sofa sinh hoạt|Khu bếp nhỏ tách khỏi vị trí ngủ'',
 N''Phòng tắm gia đình|Vòi sen và bồn tắm theo cấu hình phòng|Kệ để đồ vệ sinh cho nhiều người|Khăn và máy sấy tóc'',
 N''Tủ lạnh|Lò vi sóng|Bếp điện tại khu bếp|Máy hút mùi hoặc thông gió bếp'',
 N''Bát đĩa và dụng cụ ăn uống cơ bản|Chỗ cất đồ cho trẻ|Hỗ trợ nôi em bé theo yêu cầu'',
 N''Gia đình có trẻ nhỏ|Gia đình cần chuẩn bị bữa ăn đơn giản'',
 N''Cần báo trước nhu cầu sử dụng bếp hoặc nôi em bé; dụng cụ bổ sung tùy tình trạng sẵn có.''
),
(
 ''P402'',N''Phòng Gia Đình'',
 N''Phòng gia đình ưu tiên không gian quây quần, với góc sofa, bàn trà và khu ăn uống thuận tiện cho nhóm nhỏ.'',
 N''Góc sofa quây quần|Bàn ăn riêng|Không gian chứa hành lý gia đình'',
 N''Khu ngủ theo cấu hình giường đã công bố|Sofa và bàn trà sinh hoạt|Bàn ăn cạnh khu bếp nhỏ|Tủ đồ và kệ hành lý dùng chung'',
 N''Khu tắm đứng tách vùng lavabo|Bồn tắm theo cấu hình phòng|Giá treo nhiều khăn|Máy sấy tóc'',
 N''Tủ lạnh|Lò vi sóng|Đèn chiếu sáng khu sinh hoạt'',
 N''Bộ dụng cụ ăn uống|Góc trò chuyện trong nhà|Hỗ trợ bàn ủi theo yêu cầu'',
 N''Gia đình có con lớn|Nhóm bạn trong giới hạn sức chứa'',
 N''Số khách tối đa được tính theo sức chứa đã công bố, không theo số ghế sofa.''
),
(
 ''P501'',N''Phòng Suite'',
 N''Phòng Suite thiên về tiếp khách và công việc, với phòng khách riêng, bàn ăn nhỏ và phòng tắm thư giãn.'',
 N''Phòng khách tiếp khách riêng|Bàn ăn nhỏ|Bồn tắm Jacuzzi'',
 N''Khu vực ngủ riêng|Phòng khách có sofa|Bàn tiếp khách hoặc bàn ăn|Bàn làm việc tách khỏi khu ngủ'',
 N''Bồn tắm Jacuzzi theo cấu hình Suite|Khu vòi sen riêng|Lavabo có mặt bàn rộng|Áo choàng, dép và máy sấy tóc'',
 N''Tủ lạnh nhỏ|Máy pha cà phê theo yêu cầu|Điện thoại tại khu tiếp khách'',
 N''Không gian tiếp khách trong phòng|Hỗ trợ bữa ăn tại phòng có tính phí|Hỗ trợ bàn ủi theo yêu cầu'',
 N''Khách công tác cần tiếp khách|Cặp đôi muốn khu sinh hoạt riêng'',
 N''Yêu cầu máy pha cà phê hoặc ăn uống riêng cần báo trước; khách ghé thăm theo quy định khách sạn.''
),
(
 ''P502'',N''Phòng Suite'',
 N''Phòng Suite chú trọng nghỉ dưỡng riêng tư, có góc đọc sách cạnh cửa kính và phòng tắm kết hợp không gian thư giãn.'',
 N''Góc đọc sách nhìn ra cửa kính|Phòng khách và bàn trà|Phòng tắm thư giãn'',
 N''Khu ngủ riêng tư|Ghế đọc sách cạnh cửa sổ|Sofa và bàn trà|Bàn trang điểm cùng tủ quần áo'',
 N''Bồn tắm Jacuzzi theo cấu hình Suite|Buồng tắm đứng|Khu lavabo và gương trang điểm|Áo choàng và bộ khăn'',
 N''Đèn đọc sách độc lập|Tủ lạnh nhỏ|Bộ dụng cụ pha cà phê'',
 N''Góc thư giãn trong nhà|Hỗ trợ ăn sáng tại phòng có tính phí|Hỗ trợ bàn ủi theo yêu cầu'',
 N''Cặp đôi nghỉ dưỡng dài ngày|Khách thích đọc sách và không gian riêng'',
 N''Ăn sáng tại phòng là dịch vụ riêng; điều kiện bữa sáng đi kèm phụ thuộc gói đặt phòng.''
),
(
 ''P601'',N''Phòng Cao Cấp'',
 N''Không gian mẫu lấy cảm hứng từ penthouse, tập trung vào sân hiên, khu tiếp khách và trải nghiệm nghỉ dưỡng riêng tư.'',
 N''Sân hiên thư giãn riêng|Khu tiếp khách rộng|Hồ bơi riêng theo cấu hình phòng'',
 N''Khu ngủ theo cấu hình giường đã công bố|Phòng khách và bàn ăn|Bếp nhỏ phục vụ sinh hoạt|Sân hiên có ghế nghỉ'',
 N''Phòng tắm có bồn tắm|Khu vòi sen riêng|Bàn lavabo để đồ cá nhân|Áo choàng, dép và máy sấy tóc'',
 N''Tủ lạnh|Thiết bị bếp nhỏ|Máy pha cà phê theo yêu cầu'',
 N''Ghế nghỉ tại sân hiên|Hỗ trợ quản gia theo lịch phục vụ|Hỗ trợ bữa ăn riêng có tính phí'',
 N''Khách ưu tiên khu ngoài trời riêng|Gia đình nghỉ dưỡng trong giới hạn sức chứa'',
 N''Sử dụng sân hiên và hồ bơi theo quy định an toàn; lịch hỗ trợ quản gia cần được xác nhận.''
),
(
 ''P602'',N''Phòng Cao Cấp'',
 N''Không gian mẫu lấy cảm hứng từ villa gia đình, chú trọng bếp, khu ăn uống và sinh hoạt chung trong nhà.'',
 N''Không gian kiểu villa gia đình|Bếp kết hợp khu ăn uống|Khu thư giãn ngoài trời'',
 N''Khu ngủ theo cấu hình giường đã công bố|Phòng khách với sofa gia đình|Bàn ăn và bếp nhỏ|Góc ngồi ngoài trời gần hồ bơi'',
 N''Phòng tắm có bồn tắm theo cấu hình phòng|Buồng tắm đứng|Khu để khăn riêng|Áo choàng và máy sấy tóc'',
 N''Tủ lạnh dung tích phục vụ gia đình|Lò vi sóng|Thiết bị bếp và thông gió bếp'',
 N''Hồ bơi riêng theo cấu hình phòng|Bộ đồ ăn gia đình|Hỗ trợ quản gia và bữa ăn riêng theo yêu cầu có tính phí'',
 N''Gia đình cần không gian quây quần|Khách thích nghỉ dưỡng kiểu villa'',
 N''Yêu cầu nấu ăn riêng cần báo trước; trẻ em cần người lớn giám sát khi sử dụng khu hồ bơi.''
);

UPDATE p SET
 mo_ta=d.mo_ta,diem_noi_bat=d.diem_noi_bat,
 khong_gian=d.khong_gian,phong_tam=d.phong_tam,
 thiet_bi=d.thiet_bi,tien_ich=d.tien_ich,
 phu_hop=d.phu_hop,luu_y=d.luu_y,
 tien_nghi_chung=N''Wi-Fi|Điều hòa|TV màn hình phẳng|Két an toàn|Ấm đun nước'',
 phien_ban_noi_dung=2,cap_nhat_luc=SYSUTCDATETIME()
FROM dbo.Room_Profiles p
JOIN @Data d ON d.room_id=p.room_id
JOIN dbo.Rooms r ON r.room_id=p.room_id
JOIN dbo.Room_Types t ON t.type_id=r.type_id AND t.ten_loai=d.ten_loai
WHERE p.la_noi_dung_mau=1 AND p.phien_ban_noi_dung<2;
';

-- =========================================================
-- 2. THANH TOÁN, HỦY VÀ HOÀN TIỀN PHÒNG
-- =========================================================

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Booking_Payments'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.Booking_Payments(
  booking_id INT NOT NULL PRIMARY KEY,
  payment_status VARCHAR(16) NOT NULL DEFAULT ''UNPAID'',
  payment_method VARCHAR(16) NULL,
  payment_reference VARCHAR(80) NULL,
  amount_paid DECIMAL(18,2) NOT NULL DEFAULT 0,
  paid_at_utc DATETIME2 NULL,
  is_demo BIT NOT NULL DEFAULT 0,
  cancellation_status VARCHAR(16) NOT NULL DEFAULT ''NONE'',
  cancellation_reason NVARCHAR(500) NULL,
  review_note NVARCHAR(500) NULL,
  cancellation_requested_at_utc DATETIME2 NULL,
  cancelled_at_utc DATETIME2 NULL,
  refund_status VARCHAR(16) NOT NULL DEFAULT ''NONE'',
  refund_requested_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
  amount_refunded DECIMAL(18,2) NOT NULL DEFAULT 0,
  refunded_at_utc DATETIME2 NULL,
  refund_reference VARCHAR(80) NULL,
  checkin_at_utc DATETIME2 NOT NULL,
  free_cancel_until_utc DATETIME2 NOT NULL,
  policy_version VARCHAR(32) NOT NULL DEFAULT ''FLEX24_V1'',
  CONSTRAINT FK_Booking_Payments_Bookings FOREIGN KEY(booking_id)
   REFERENCES dbo.Bookings(booking_id),
  CONSTRAINT CK_Booking_Payments_Status
   CHECK(payment_status IN(''UNPAID'',''PENDING'',''PAID'')),
  CONSTRAINT CK_Booking_Payments_Method
   CHECK(payment_method IS NULL OR payment_method IN(''BANK'',''MOMO'',''CARD'')),
  CONSTRAINT CK_Booking_Payments_Cancellation
   CHECK(cancellation_status IN(''NONE'',''REQUESTED'',''CANCELLED'',''DENIED'')),
  CONSTRAINT CK_Booking_Payments_Refund
   CHECK(refund_status IN(''NONE'',''REVIEW'',''PENDING'',''REFUNDED'',''REJECTED'')),
  CONSTRAINT CK_Booking_Payments_Amounts CHECK(
   amount_paid>=0 AND amount_refunded>=0
   AND amount_refunded<=amount_paid
   AND refund_requested_amount>=0
   AND refund_requested_amount<=amount_paid
  ),
  CONSTRAINT CK_Booking_Payments_Paid CHECK(
   (payment_status IN(''UNPAID'',''PENDING'')
    AND amount_paid=0 AND paid_at_utc IS NULL)
   OR
   (payment_status=''PAID'' AND paid_at_utc IS NOT NULL
    AND payment_reference IS NOT NULL AND payment_method IS NOT NULL)
  ),
  CONSTRAINT CK_Booking_Payments_Refunded CHECK(
   refund_status<>''REFUNDED''
   OR
   (payment_status=''PAID'' AND refunded_at_utc IS NOT NULL
    AND refund_reference IS NOT NULL
    AND amount_refunded=refund_requested_amount)
  ),
  CONSTRAINT CK_Booking_Payments_Cancelled
   CHECK(cancellation_status<>''CANCELLED'' OR cancelled_at_utc IS NOT NULL)
 );
END;
';

EXEC sys.sp_executesql N'
IF NOT EXISTS(
 SELECT 1 FROM sys.indexes
 WHERE object_id=OBJECT_ID(N''dbo.Booking_Payments'')
 AND name=N''UX_Booking_Payments_PaymentRef''
)
 CREATE UNIQUE INDEX UX_Booking_Payments_PaymentRef
 ON dbo.Booking_Payments(payment_reference)
 WHERE payment_reference IS NOT NULL;
IF NOT EXISTS(
 SELECT 1 FROM sys.indexes
 WHERE object_id=OBJECT_ID(N''dbo.Booking_Payments'')
 AND name=N''UX_Booking_Payments_RefundRef''
)
 CREATE UNIQUE INDEX UX_Booking_Payments_RefundRef
 ON dbo.Booking_Payments(refund_reference)
 WHERE refund_reference IS NOT NULL;
';

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Booking_Payment_Events'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.Booking_Payment_Events(
  event_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  booking_id INT NOT NULL,
  event_type VARCHAR(32) NOT NULL,
  amount DECIMAL(18,2) NOT NULL DEFAULT 0,
  reference VARCHAR(80) NOT NULL,
  is_demo BIT NOT NULL DEFAULT 0,
  created_at_utc DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT FK_Booking_Payment_Events_Bookings FOREIGN KEY(booking_id)
   REFERENCES dbo.Bookings(booking_id),
  CONSTRAINT UQ_Booking_Payment_Events_Once UNIQUE(booking_id,event_type),
  CONSTRAINT UQ_Booking_Payment_Events_Reference UNIQUE(reference),
  CONSTRAINT CK_Booking_Payment_Events_Amount CHECK(amount>=0)
 );
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.ConfirmBankPayment
 @booking_id INT,@amount_received DECIMAL(18,2),
 @bank_transaction_reference VARCHAR(80)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET @bank_transaction_reference=LTRIM(RTRIM(@bank_transaction_reference));
 IF NULLIF(@bank_transaction_reference,'''') IS NULL
  THROW 51000,N''Phải nhập mã giao dịch ngân hàng thực tế.'',1;
 BEGIN TRANSACTION;
 DECLARE @total DECIMAL(18,2),@status NVARCHAR(50);
 SELECT @total=tong_tien,@status=trang_thai
 FROM dbo.Bookings WITH(UPDLOCK,HOLDLOCK) WHERE booking_id=@booking_id;
 IF @total IS NULL OR @total<=0 OR @amount_received<>@total
    OR @amount_received IS NULL
 BEGIN
  ROLLBACK;
  THROW 51000,N''Số tiền thực nhận phải khớp chính xác tổng tiền đơn.'',1;
 END;
 IF NOT EXISTS(
  SELECT 1 FROM dbo.Booking_Payments
  WHERE booking_id=@booking_id AND payment_method=''BANK''
 )
 BEGIN
  ROLLBACK;
  THROW 51000,N''Đơn chưa chọn chuyển khoản ngân hàng trên web.'',1;
 END;
 IF EXISTS(
  SELECT 1 FROM dbo.Booking_Payments
  WHERE booking_id=@booking_id AND payment_status=''PAID''
 )
 BEGIN
  IF EXISTS(
   SELECT 1 FROM dbo.Booking_Payments
   WHERE booking_id=@booking_id
    AND payment_reference=@bank_transaction_reference
    AND amount_paid=@amount_received
  )
  BEGIN COMMIT; RETURN; END;
  ROLLBACK;
  THROW 51000,N''Đơn đã xác nhận bằng giao dịch khác. Cần kiểm tra khoản chuyển thừa.'',1;
 END;
 UPDATE dbo.Booking_Payments
 SET payment_status=''PAID'',amount_paid=@amount_received,
  payment_reference=@bank_transaction_reference,
  paid_at_utc=SYSUTCDATETIME(),is_demo=0,
  refund_requested_amount=CASE
   WHEN cancellation_status IN(''CANCELLED'',''REQUESTED'')
   THEN @amount_received ELSE 0 END,
  refund_status=CASE
   WHEN cancellation_status=''REQUESTED'' THEN ''REVIEW''
   WHEN cancellation_status=''CANCELLED'' THEN ''PENDING''
   ELSE refund_status END
 WHERE booking_id=@booking_id;
 UPDATE dbo.Bookings SET trang_thai=N''Đã xác nhận''
 WHERE booking_id=@booking_id
  AND trang_thai IN(N''Chờ thanh toán'',N''Chờ đối soát'',N''Chờ xác nhận'');
 INSERT dbo.Booking_Payment_Events(booking_id,event_type,amount,reference)
 VALUES(@booking_id,''PAYMENT_CONFIRMED'',@amount_received,
        CONVERT(VARCHAR(36),NEWID()));
 COMMIT;
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.ReviewBookingCancellation
 @booking_id INT,@approve BIT,@refund_amount DECIMAL(18,2),
 @note NVARCHAR(500)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @approve IS NULL OR NULLIF(LTRIM(RTRIM(@note)),N'''') IS NULL
  THROW 51000,N''Phải nhập quyết định và ghi chú xét hủy.'',1;
 BEGIN TRANSACTION;
 DECLARE @id INT,@paid DECIMAL(18,2),@payment VARCHAR(16),@checkin DATETIME2;
 SELECT @id=booking_id FROM dbo.Bookings WITH(UPDLOCK,HOLDLOCK)
 WHERE booking_id=@booking_id;
 SELECT @paid=amount_paid,@payment=payment_status,@checkin=checkin_at_utc
 FROM dbo.Booking_Payments
 WHERE booking_id=@booking_id AND cancellation_status=''REQUESTED'';
 IF @paid IS NULL
 BEGIN ROLLBACK; THROW 51000,N''Không có yêu cầu hủy đang chờ xét.'',1; END;
 IF SYSUTCDATETIME()>=@checkin
 BEGIN
  ROLLBACK;
  THROW 51000,N''Đã đến giờ nhận phòng; cần xử lý nghiệp vụ trực tiếp tại khách sạn.'',1;
 END;
 IF @approve=1 AND @payment=''PENDING'' AND ISNULL(@refund_amount,-1)<>0
 BEGIN
  ROLLBACK;
  THROW 51000,N''Chưa đối soát thì không xác nhận tiền hoàn. Nếu kiểm tra chưa nhận tiền, chỉ duyệt hủy với số tiền hoàn bằng 0.'',1;
 END;
 IF @approve=1
  AND (@refund_amount IS NULL OR @refund_amount<0 OR @refund_amount>@paid)
 BEGIN ROLLBACK; THROW 51000,N''Số tiền hoàn không hợp lệ.'',1; END;
 UPDATE dbo.Booking_Payments SET
  cancellation_status=CASE WHEN @approve=1 THEN ''CANCELLED'' ELSE ''DENIED'' END,
  payment_status=CASE WHEN @approve=1 AND @payment=''PENDING''
   THEN ''UNPAID'' ELSE payment_status END,
  cancelled_at_utc=CASE WHEN @approve=1 THEN SYSUTCDATETIME() ELSE NULL END,
  review_note=@note,
  refund_requested_amount=CASE WHEN @approve=1 THEN @refund_amount ELSE 0 END,
  refund_status=CASE WHEN @approve=0 THEN ''REJECTED''
   WHEN @refund_amount>0 THEN ''PENDING'' ELSE ''NONE'' END
 WHERE booking_id=@booking_id;
 IF @approve=1
  UPDATE dbo.Bookings SET trang_thai=N''Đã hủy''
  WHERE booking_id=@booking_id;
 INSERT dbo.Booking_Payment_Events(booking_id,event_type,amount,reference)
 VALUES(@booking_id,
  CASE WHEN @approve=1 THEN ''CANCELLED'' ELSE ''CANCEL_DENIED'' END,
  0,CONVERT(VARCHAR(36),NEWID()));
 COMMIT;
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.ConfirmBankRefund
 @booking_id INT,@amount_refunded DECIMAL(18,2),
 @bank_refund_reference VARCHAR(80)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET @bank_refund_reference=LTRIM(RTRIM(@bank_refund_reference));
 IF NULLIF(@bank_refund_reference,'''') IS NULL
  THROW 51000,N''Phải nhập mã giao dịch hoàn tiền thực tế.'',1;
 BEGIN TRANSACTION;
 DECLARE @id INT;
 SELECT @id=booking_id FROM dbo.Bookings WITH(UPDLOCK,HOLDLOCK)
 WHERE booking_id=@booking_id;
 IF EXISTS(
  SELECT 1 FROM dbo.Booking_Payments
  WHERE booking_id=@booking_id AND refund_status=''REFUNDED''
   AND refund_reference=@bank_refund_reference
   AND amount_refunded=@amount_refunded
 )
 BEGIN COMMIT; RETURN; END;
 IF NOT EXISTS(
  SELECT 1 FROM dbo.Booking_Payments
  WHERE booking_id=@booking_id AND payment_status=''PAID''
   AND cancellation_status=''CANCELLED'' AND refund_status=''PENDING''
   AND refund_requested_amount=@amount_refunded AND @amount_refunded>0
 )
 BEGIN
  ROLLBACK;
  THROW 51000,N''Đơn hoặc số tiền hoàn không khớp yêu cầu đang chờ.'',1;
 END;
 UPDATE dbo.Booking_Payments
 SET refund_status=''REFUNDED'',amount_refunded=@amount_refunded,
  refunded_at_utc=SYSUTCDATETIME(),refund_reference=@bank_refund_reference
 WHERE booking_id=@booking_id;
 INSERT dbo.Booking_Payment_Events(booking_id,event_type,amount,reference)
 VALUES(@booking_id,''REFUND_CONFIRMED'',@amount_refunded,
        CONVERT(VARCHAR(36),NEWID()));
 COMMIT;
END;
';

-- =========================================================
-- 3. NỀN DỊCH VỤ ĂN UỐNG / THƯ GIÃN
-- =========================================================

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Dining_Services'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.Dining_Services(
  service_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  service_code VARCHAR(30) NOT NULL UNIQUE,
  service_group VARCHAR(16) NOT NULL DEFAULT ''DINING'',
  service_name NVARCHAR(150) NOT NULL,
  description NVARCHAR(800) NULL,
  pricing_mode VARCHAR(20) NOT NULL,
  unit_price DECIMAL(18,2) NULL,
  image_url NVARCHAR(1000) NULL,
  enabled BIT NOT NULL DEFAULT 1
 );
END;
';

EXEC sys.sp_executesql N'
IF COL_LENGTH(N''dbo.Dining_Services'',N''service_group'') IS NULL
 ALTER TABLE dbo.Dining_Services
 ADD service_group VARCHAR(16) NOT NULL DEFAULT ''DINING'';
';

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Dining_Slots'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.Dining_Slots(
  slot_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  service_id INT NOT NULL,start_time TIME(0) NOT NULL,
  enabled BIT NOT NULL DEFAULT 1,
  CONSTRAINT FK_Dining_Slots_Service FOREIGN KEY(service_id)
   REFERENCES dbo.Dining_Services(service_id),
  CONSTRAINT UQ_Dining_Slots_Time UNIQUE(service_id,start_time),
  CONSTRAINT UQ_Dining_Slots_ServicePair UNIQUE(slot_id,service_id)
 );
END;
';

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Dining_Reservations'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.Dining_Reservations(
  reservation_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  public_code VARCHAR(24) NOT NULL UNIQUE,
  request_token UNIQUEIDENTIFIER NOT NULL UNIQUE,
  service_id INT NOT NULL,slot_id INT NOT NULL,
  service_group VARCHAR(16) NOT NULL DEFAULT ''DINING'',
  service_name NVARCHAR(150) NOT NULL,
  visit_at DATETIME2 NOT NULL,guests INT NOT NULL,
  pricing_mode VARCHAR(20) NOT NULL,
  unit_price DECIMAL(18,2) NULL,estimated_total DECIMAL(18,2) NULL,
  full_name NVARCHAR(150) NOT NULL,phone VARCHAR(20) NOT NULL,
  email NVARCHAR(255) NULL,notes NVARCHAR(1000) NULL,
  status VARCHAR(16) NOT NULL DEFAULT ''PENDING'',
  staff_note NVARCHAR(1000) NULL,cancellation_reason NVARCHAR(500) NULL,
  created_at_utc DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at_utc DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  cancelled_at_utc DATETIME2 NULL,
  CONSTRAINT FK_Dining_Reservations_Slot FOREIGN KEY(slot_id,service_id)
   REFERENCES dbo.Dining_Slots(slot_id,service_id),
  CONSTRAINT CK_Dining_Reservations_Guests CHECK(guests BETWEEN 1 AND 20),
  CONSTRAINT CK_Dining_Reservations_Status
   CHECK(status IN(''PENDING'',''CONFIRMED'',''CANCELLED'',''DECLINED'',''COMPLETED'')),
  CONSTRAINT CK_Dining_Reservations_Cancelled
   CHECK(status<>''CANCELLED'' OR cancelled_at_utc IS NOT NULL)
 );
END;
';

EXEC sys.sp_executesql N'
IF COL_LENGTH(N''dbo.Dining_Reservations'',N''service_group'') IS NULL
 ALTER TABLE dbo.Dining_Reservations
 ADD service_group VARCHAR(16) NOT NULL DEFAULT ''DINING'';
';

EXEC sys.sp_executesql N'
BEGIN TRANSACTION;
IF EXISTS(
 SELECT 1 FROM sys.check_constraints
 WHERE parent_object_id=OBJECT_ID(N''dbo.Dining_Services'')
 AND name=N''CK_Dining_Services_Price''
)
 ALTER TABLE dbo.Dining_Services DROP CONSTRAINT CK_Dining_Services_Price;
ALTER TABLE dbo.Dining_Services WITH CHECK
ADD CONSTRAINT CK_Dining_Services_Price CHECK(
 (pricing_mode=''PER_PERSON'' AND unit_price IS NOT NULL AND unit_price>=0)
 OR
 (pricing_mode IN(''A_LA_CARTE'',''REQUEST_QUOTE'') AND unit_price IS NULL)
);
IF EXISTS(
 SELECT 1 FROM sys.check_constraints
 WHERE parent_object_id=OBJECT_ID(N''dbo.Dining_Reservations'')
 AND name=N''CK_Dining_Reservations_Price''
)
 ALTER TABLE dbo.Dining_Reservations DROP CONSTRAINT CK_Dining_Reservations_Price;
ALTER TABLE dbo.Dining_Reservations WITH CHECK
ADD CONSTRAINT CK_Dining_Reservations_Price CHECK(
 (pricing_mode=''PER_PERSON'' AND unit_price IS NOT NULL AND unit_price>=0
  AND estimated_total IS NOT NULL AND estimated_total=unit_price*guests)
 OR
 (pricing_mode IN(''A_LA_CARTE'',''REQUEST_QUOTE'')
  AND unit_price IS NULL AND estimated_total IS NULL)
);
IF NOT EXISTS(
 SELECT 1 FROM sys.check_constraints
 WHERE parent_object_id=OBJECT_ID(N''dbo.Dining_Services'')
 AND name=N''CK_Dining_Services_Group''
)
 ALTER TABLE dbo.Dining_Services WITH CHECK
 ADD CONSTRAINT CK_Dining_Services_Group
 CHECK(service_group IN(''DINING'',''WELLNESS''));
IF NOT EXISTS(
 SELECT 1 FROM sys.check_constraints
 WHERE parent_object_id=OBJECT_ID(N''dbo.Dining_Reservations'')
 AND name=N''CK_Dining_Reservations_Group''
)
 ALTER TABLE dbo.Dining_Reservations WITH CHECK
 ADD CONSTRAINT CK_Dining_Reservations_Group
 CHECK(service_group IN(''DINING'',''WELLNESS''));

INSERT dbo.Dining_Services(
 service_code,service_group,service_name,description,
 pricing_mode,unit_price,image_url
)
SELECT v.code,v.group_code,v.name,v.description,v.mode,v.price,v.image
FROM(VALUES
(''BREAKFAST'',''DINING'',N''Buffet sáng'',
 N''Đặt chỗ dùng buffet sáng tại nhà hàng. Giá ước tính tính theo số người đăng ký.'',
 ''PER_PERSON'',CONVERT(DECIMAL(18,2),150000),
 N''https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=1000&q=80''),
(''LUNCH'',''DINING'',N''Đặt bàn ăn trưa'',
 N''Đặt bàn cho gia đình, bạn bè hoặc khách công tác. Chi phí theo thực đơn và món gọi thực tế.'',
 ''A_LA_CARTE'',NULL,
 N''https://images.unsplash.com/photo-1414235077428-338989a2e8c0?auto=format&fit=crop&w=1000&q=80''),
(''DINNER'',''DINING'',N''Đặt bàn ăn tối'',
 N''Đặt bàn cho buổi tối hoặc dịp đặc biệt. Bạn có thể ghi chú mong muốn về vị trí ngồi.'',
 ''A_LA_CARTE'',NULL,
 N''https://images.unsplash.com/photo-1552566626-52f8b828add9?auto=format&fit=crop&w=1000&q=80''),
(''POOL'',''WELLNESS'',N''Tắm hồ bơi'',
 N''Đăng ký lượt sử dụng hồ bơi cho khách vãng lai. Nhân viên sẽ xác nhận khung giờ phục vụ, giá và hướng dẫn khi đến.'',
 ''REQUEST_QUOTE'',NULL,
 N''https://images.unsplash.com/photo-1576013551627-0cc20b96c2a7?auto=format&fit=crop&w=1000&q=80''),
(''MASSAGE'',''WELLNESS'',N''Massage thư giãn — 60 phút'',
 N''Đăng ký buổi massage thư giãn. Nhân viên sẽ liên hệ để thống nhất loại liệu trình, giá và lịch phục vụ.'',
 ''REQUEST_QUOTE'',NULL,
 N''https://images.unsplash.com/photo-1544161515-4ab6ce6db874?auto=format&fit=crop&w=1000&q=80''),
(''GYM'',''WELLNESS'',N''Phòng tập GYM'',
 N''Đăng ký lượt tập GYM tại khách sạn. Chọn ngày, khung giờ và số người; nhân viên sẽ kiểm tra và xác nhận yêu cầu.'',
 ''REQUEST_QUOTE'',NULL,
 N''https://images.unsplash.com/photo-1534438327276-14e5300c3a48?auto=format&fit=crop&w=1000&q=80''),
(''SAUNA'',''WELLNESS'',N''Xông hơi — 45 phút'',
 N''Đăng ký buổi xông hơi thư giãn. Bạn có thể ghi chú mong muốn xông khô hoặc xông ướt để nhân viên tư vấn và xác nhận.'',
 ''REQUEST_QUOTE'',NULL,
 N''https://images.unsplash.com/photo-1540555700478-4be289fbecef?auto=format&fit=crop&w=1000&q=80''),
(''YOGA'',''WELLNESS'',N''Yoga cùng HLV — 60 phút'',
 N''Đăng ký buổi Yoga cùng huấn luyện viên. Lịch học, số chỗ và giá được nhân viên xác nhận trước khi bạn đến.'',
 ''REQUEST_QUOTE'',NULL,
 N''https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?auto=format&fit=crop&w=1000&q=80'')
)v(code,group_code,name,description,mode,price,image)
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.Dining_Services s WHERE s.service_code=v.code
);

UPDATE dbo.Dining_Services SET service_group=''WELLNESS''
WHERE service_code IN(''POOL'',''MASSAGE'',''GYM'',''SAUNA'',''YOGA'');
UPDATE r SET service_group=s.service_group
FROM dbo.Dining_Reservations r
JOIN dbo.Dining_Services s ON s.service_id=r.service_id
WHERE r.service_group=''DINING'' AND s.service_group=''WELLNESS'';

INSERT dbo.Dining_Slots(service_id,start_time)
SELECT s.service_id,CONVERT(TIME(0),v.start_time)
FROM(VALUES
(''BREAKFAST'',''07:00''),(''BREAKFAST'',''07:30''),
(''BREAKFAST'',''08:00''),(''BREAKFAST'',''08:30''),(''BREAKFAST'',''09:00''),
(''LUNCH'',''11:00''),(''LUNCH'',''11:30''),(''LUNCH'',''12:00''),
(''LUNCH'',''12:30''),(''LUNCH'',''13:00''),
(''DINNER'',''18:00''),(''DINNER'',''18:30''),(''DINNER'',''19:00''),
(''DINNER'',''19:30''),(''DINNER'',''20:00''),
(''POOL'',''08:00''),(''POOL'',''10:00''),(''POOL'',''14:00''),(''POOL'',''16:00''),
(''MASSAGE'',''09:00''),(''MASSAGE'',''10:00''),(''MASSAGE'',''11:00''),
(''MASSAGE'',''14:00''),(''MASSAGE'',''15:00''),(''MASSAGE'',''16:00''),
(''GYM'',''06:30''),(''GYM'',''08:00''),(''GYM'',''10:00''),
(''GYM'',''14:00''),(''GYM'',''16:00''),(''GYM'',''18:00''),
(''SAUNA'',''09:00''),(''SAUNA'',''10:00''),(''SAUNA'',''14:00''),
(''SAUNA'',''15:00''),(''SAUNA'',''16:00''),(''SAUNA'',''17:00''),
(''YOGA'',''06:30''),(''YOGA'',''08:00''),(''YOGA'',''16:00''),(''YOGA'',''17:30'')
)v(code,start_time)
JOIN dbo.Dining_Services s ON s.service_code=v.code
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.Dining_Slots t
 WHERE t.service_id=s.service_id
 AND t.start_time=CONVERT(TIME(0),v.start_time)
);
COMMIT;
';

EXEC sys.sp_executesql N'
IF NOT EXISTS(
 SELECT 1 FROM sys.indexes
 WHERE object_id=OBJECT_ID(N''dbo.Dining_Reservations'')
 AND name=N''IX_Dining_Reservations_VisitStatus''
)
 CREATE INDEX IX_Dining_Reservations_VisitStatus
 ON dbo.Dining_Reservations(visit_at,status);
';

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Dining_ServiceInventory'',N''U'') IS NULL
CREATE TABLE dbo.Dining_ServiceInventory(
 service_id INT NOT NULL PRIMARY KEY REFERENCES dbo.Dining_Services(service_id),
 capacity INT NOT NULL CHECK(capacity BETWEEN 1 AND 200),
 duration_minutes INT NOT NULL CHECK(duration_minutes BETWEEN 15 AND 480),
 enabled BIT NOT NULL DEFAULT 1,
 is_sample BIT NOT NULL DEFAULT 1
);
';

-- CẤU HÌNH MẪU:
-- Hồ bơi 20 chỗ/120 phút; massage 3 chỗ/60 phút;
-- GYM 10 chỗ/90 phút; xông hơi 4 chỗ/45 phút; Yoga 12 chỗ/60 phút.
EXEC sys.sp_executesql N'
BEGIN TRANSACTION;
UPDATE s SET pricing_mode=''PER_PERSON'',unit_price=v.price,
 description=v.description
FROM dbo.Dining_Services s
JOIN(VALUES
(''POOL'',150000,N''Sử dụng hồ bơi trong một lượt 120 phút. Giá tính theo người.''),
(''MASSAGE'',350000,N''Massage thư giãn 60 phút, một kỹ thuật viên phục vụ mỗi khách.''),
(''GYM'',100000,N''Sử dụng phòng tập GYM trong một lượt 90 phút. Giá tính theo người.''),
(''SAUNA'',200000,N''Xông hơi thư giãn 45 phút. Giá tính theo người.''),
(''YOGA'',150000,N''Buổi Yoga 60 phút cùng huấn luyện viên. Giá tính theo học viên.'')
)v(code,price,description) ON v.code=s.service_code
WHERE s.pricing_mode=''REQUEST_QUOTE'' AND s.unit_price IS NULL;

INSERT dbo.Dining_ServiceInventory(service_id,capacity,duration_minutes)
SELECT s.service_id,v.capacity,v.duration
FROM(VALUES
(''POOL'',20,120),(''MASSAGE'',3,60),(''GYM'',10,90),
(''SAUNA'',4,45),(''YOGA'',12,60)
)v(code,capacity,duration)
JOIN dbo.Dining_Services s ON s.service_code=v.code
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.Dining_ServiceInventory i WHERE i.service_id=s.service_id
);
COMMIT;
';

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Dining_ServicePayments'',N''U'') IS NULL
CREATE TABLE dbo.Dining_ServicePayments(
 reservation_id INT NOT NULL PRIMARY KEY
  REFERENCES dbo.Dining_Reservations(reservation_id),
 payment_percent INT NOT NULL CHECK(payment_percent IN(30,100)),
 total_amount DECIMAL(18,2) NOT NULL CHECK(total_amount>0),
 required_amount DECIMAL(18,2) NOT NULL CHECK(required_amount>0),
 paid_amount DECIMAL(18,2) NOT NULL DEFAULT 0 CHECK(paid_amount>=0),
 refunded_amount DECIMAL(18,2) NOT NULL DEFAULT 0 CHECK(refunded_amount>=0),
 duration_minutes INT NOT NULL CHECK(duration_minutes BETWEEN 15 AND 480),
 hold_until_utc DATETIME2 NOT NULL,
 client_hash BINARY(32) NOT NULL,
 payment_status VARCHAR(20) NOT NULL DEFAULT ''WAITING''
  CHECK(payment_status IN(
   ''WAITING'',''REPORTED'',''DEPOSIT_PAID'',''PAID'',''REVIEW'',
   ''REFUND_REVIEW'',''REFUNDED'',''PART_REFUND''
  )),
 cancel_requested_at_utc DATETIME2 NULL,
 staff_note NVARCHAR(1000) NULL,
 created_at_utc DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
 CHECK(required_amount=CEILING(total_amount*payment_percent/100)),
 CHECK(required_amount<=total_amount),
 CHECK(refunded_amount<=paid_amount)
);
';

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Dining_ServiceTransfers'',N''U'') IS NULL
CREATE TABLE dbo.Dining_ServiceTransfers(
 transfer_id INT IDENTITY PRIMARY KEY,
 reservation_id INT NOT NULL REFERENCES dbo.Dining_ServicePayments(reservation_id),
 bank_reference VARCHAR(100) NOT NULL UNIQUE,
 amount DECIMAL(18,2) NOT NULL CHECK(amount>0),
 verified_by SYSNAME NOT NULL DEFAULT ORIGINAL_LOGIN(),
 verified_at_utc DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
IF OBJECT_ID(N''dbo.Dining_ServiceRefunds'',N''U'') IS NULL
CREATE TABLE dbo.Dining_ServiceRefunds(
 refund_id INT IDENTITY PRIMARY KEY,
 reservation_id INT NOT NULL REFERENCES dbo.Dining_ServicePayments(reservation_id),
 bank_reference VARCHAR(100) NOT NULL UNIQUE,
 amount DECIMAL(18,2) NOT NULL CHECK(amount>0),
 verified_by SYSNAME NOT NULL DEFAULT ORIGINAL_LOGIN(),
 verified_at_utc DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
';

-- Luồng tư vấn/đặt bàn gọi món được giữ riêng.
EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.SetDiningReservationStatus_Legacy
 @public_code VARCHAR(24),@status VARCHAR(16),
 @note NVARCHAR(1000)=NULL,@unit_price DECIMAL(18,2)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET @public_code=UPPER(LTRIM(RTRIM(@public_code)));
 SET @status=UPPER(LTRIM(RTRIM(@status)));
 IF @status IS NULL OR @status NOT IN(''CONFIRMED'',''DECLINED'',''COMPLETED'')
  THROW 51000,N''Trạng thái không hợp lệ.'',1;
 IF @status=''DECLINED'' AND NULLIF(LTRIM(RTRIM(@note)),N'''') IS NULL
  THROW 51000,N''Vui lòng nhập lý do từ chối.'',1;
 BEGIN TRANSACTION;
 DECLARE @old_status VARCHAR(16),@mode VARCHAR(20),@guests INT,
  @visit_at DATETIME2,@now_vn DATETIME2=DATEADD(HOUR,7,SYSUTCDATETIME());
 SELECT @old_status=status,@mode=pricing_mode,
  @guests=guests,@visit_at=visit_at
 FROM dbo.Dining_Reservations WITH(UPDLOCK,HOLDLOCK)
 WHERE public_code=@public_code;
 IF @old_status IS NULL
 BEGIN ROLLBACK; THROW 51000,N''Không tìm thấy mã đặt dịch vụ.'',1; END;
 IF @old_status=@status BEGIN COMMIT; RETURN; END;
 IF NOT(
  (@old_status=''PENDING'' AND @status=''CONFIRMED'' AND @visit_at>@now_vn)
  OR (@old_status=''PENDING'' AND @status=''DECLINED'')
  OR (@old_status=''CONFIRMED'' AND @status=''COMPLETED'' AND @visit_at<=@now_vn)
 )
 BEGIN ROLLBACK; THROW 51000,N''Không thể chuyển trạng thái yêu cầu này.'',1; END;
 IF @status=''CONFIRMED'' AND @mode=''REQUEST_QUOTE''
  AND (@unit_price IS NULL OR @unit_price<0)
 BEGIN
  ROLLBACK;
  THROW 51000,N''Phải nhập giá/người đã thống nhất với khách trước khi xác nhận.'',1;
 END;
 IF @unit_price IS NOT NULL
  AND NOT(@status=''CONFIRMED'' AND @mode=''REQUEST_QUOTE'')
 BEGIN
  ROLLBACK;
  THROW 51000,N''Tham số giá chỉ dùng khi xác nhận yêu cầu đang chờ báo giá.'',1;
 END;
 UPDATE dbo.Dining_Reservations SET
  status=@status,
  pricing_mode=CASE WHEN @status=''CONFIRMED'' AND @mode=''REQUEST_QUOTE''
   THEN ''PER_PERSON'' ELSE pricing_mode END,
  unit_price=CASE WHEN @status=''CONFIRMED'' AND @mode=''REQUEST_QUOTE''
   THEN @unit_price ELSE unit_price END,
  estimated_total=CASE WHEN @status=''CONFIRMED'' AND @mode=''REQUEST_QUOTE''
   THEN @unit_price*@guests ELSE estimated_total END,
  staff_note=NULLIF(LTRIM(RTRIM(@note)),N''''),
  updated_at_utc=SYSUTCDATETIME()
 WHERE public_code=@public_code;
 COMMIT;
END;
';

-- =========================================================
-- 4. COMBO VÀ SỨC CHỨA DÙNG CHUNG
-- =========================================================

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Dining_Combos'',N''U'') IS NULL
CREATE TABLE dbo.Dining_Combos(
 service_id INT NOT NULL PRIMARY KEY REFERENCES dbo.Dining_Services(service_id),
 is_sample BIT NOT NULL DEFAULT 1
);
IF OBJECT_ID(N''dbo.Dining_ComboItems'',N''U'') IS NULL
CREATE TABLE dbo.Dining_ComboItems(
 combo_service_id INT NOT NULL REFERENCES dbo.Dining_Combos(service_id),
 component_service_id INT NOT NULL REFERENCES dbo.Dining_Services(service_id),
 start_offset_minutes INT NOT NULL CHECK(start_offset_minutes BETWEEN 0 AND 480),
 duration_minutes INT NOT NULL CHECK(duration_minutes BETWEEN 15 AND 480),
 PRIMARY KEY(combo_service_id,component_service_id),
 CHECK(combo_service_id<>component_service_id),
 CHECK(start_offset_minutes+duration_minutes<=480)
);
IF OBJECT_ID(N''dbo.Dining_ServiceAllocations'',N''U'') IS NULL
CREATE TABLE dbo.Dining_ServiceAllocations(
 reservation_id INT NOT NULL REFERENCES dbo.Dining_Reservations(reservation_id),
 service_id INT NOT NULL REFERENCES dbo.Dining_Services(service_id),
 service_name NVARCHAR(150) NOT NULL,
 visit_at DATETIME2 NOT NULL,
 duration_minutes INT NOT NULL CHECK(duration_minutes BETWEEN 15 AND 480),
 guests INT NOT NULL CHECK(guests BETWEEN 1 AND 20),
 PRIMARY KEY(reservation_id,service_id)
);
IF NOT EXISTS(
 SELECT 1 FROM sys.indexes
 WHERE object_id=OBJECT_ID(N''dbo.Dining_ServiceAllocations'')
 AND name=N''IX_ServiceAllocations_ResourceTime''
)
 CREATE INDEX IX_ServiceAllocations_ResourceTime
 ON dbo.Dining_ServiceAllocations(service_id,visit_at)
 INCLUDE(reservation_id,duration_minutes,guests);
';

EXEC sys.sp_executesql N'
DECLARE @seeds TABLE(
 code VARCHAR(30),name NVARCHAR(150),description NVARCHAR(800),
 price DECIMAL(18,2),duration INT,photo_code VARCHAR(30)
);
INSERT @seeds VALUES
(''COMBO_NANG_DONG'',N''Combo Năng động'',
 N''GYM 90 phút, nghỉ 30 phút, sau đó hồ bơi 120 phút. Tổng lịch 4 giờ. Lịch từng dịch vụ được ghi trên phiếu đặt.'',
 220000,240,''POOL''),
(''COMBO_HOI_PHUC'',N''Combo Hồi phục'',
 N''GYM 90 phút, nghỉ 30 phút, sau đó xông hơi 45 phút. Tổng lịch 2 giờ 45 phút.'',
 260000,165,''GYM''),
(''COMBO_THU_GIAN'',N''Combo Thư giãn'',
 N''Xông hơi 45 phút, nghỉ 15 phút, sau đó massage thư giãn 60 phút. Tổng lịch 2 giờ.'',
 490000,120,''MASSAGE''),
(''COMBO_BINH_MINH'',N''Combo Bình minh'',
 N''Yoga cùng HLV 60 phút, nghỉ 30 phút, sau đó hồ bơi 120 phút. Bắt đầu 06:30, kết thúc 10:00.'',
 260000,210,''YOGA''),
(''COMBO_TRON_VEN'',N''Combo Thư giãn trọn vẹn'',
 N''Xông hơi 45 phút, nghỉ 15 phút, massage 60 phút rồi hồ bơi 120 phút. Bắt đầu 14:00, kết thúc 18:00.'',
 650000,240,''MASSAGE'');

IF(
 SELECT COUNT(*) FROM dbo.Dining_Services s
 JOIN dbo.Dining_ServiceInventory i ON i.service_id=s.service_id
 WHERE s.service_code IN(''POOL'',''MASSAGE'',''GYM'',''SAUNA'',''YOGA'')
 AND s.pricing_mode=''PER_PERSON'' AND s.unit_price>0
)<>5
 THROW 51000,N''Phải có đủ 5 dịch vụ lẻ và giá/sức chứa của chúng trước khi thêm combo.'',1;

IF EXISTS(
 SELECT 1 FROM @seeds v JOIN dbo.Dining_Services s ON s.service_code=v.code
 WHERE NOT EXISTS(
  SELECT 1 FROM dbo.Dining_Combos c WHERE c.service_id=s.service_id
 )
 AND EXISTS(
  SELECT 1 FROM dbo.Dining_Reservations r WHERE r.service_id=s.service_id
 )
)
 THROW 51000,N''Mã combo đã được dùng bởi dịch vụ có đơn cũ. Cần kiểm tra trước khi đổi cấu trúc.'',1;

INSERT dbo.Dining_Services(
 service_code,service_group,service_name,description,
 pricing_mode,unit_price,image_url
)
SELECT v.code,''WELLNESS'',v.name,v.description,''PER_PERSON'',v.price,p.image_url
FROM @seeds v LEFT JOIN dbo.Dining_Services p ON p.service_code=v.photo_code
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.Dining_Services s WHERE s.service_code=v.code
);

DECLARE @new TABLE(service_id INT PRIMARY KEY);
INSERT dbo.Dining_Combos(service_id)
OUTPUT inserted.service_id INTO @new
SELECT s.service_id FROM @seeds v
JOIN dbo.Dining_Services s ON s.service_code=v.code
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.Dining_Combos c WHERE c.service_id=s.service_id
);

INSERT dbo.Dining_ServiceInventory(
 service_id,capacity,duration_minutes,is_sample
)
SELECT s.service_id,20,v.duration,1
FROM @new n JOIN dbo.Dining_Services s ON s.service_id=n.service_id
JOIN @seeds v ON v.code=s.service_code
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.Dining_ServiceInventory i WHERE i.service_id=s.service_id
);

INSERT dbo.Dining_ComboItems(
 combo_service_id,component_service_id,start_offset_minutes,duration_minutes
)
SELECT c.service_id,p.service_id,v.offset_minutes,v.duration
FROM(VALUES
(''COMBO_NANG_DONG'',''GYM'',0,90),(''COMBO_NANG_DONG'',''POOL'',120,120),
(''COMBO_HOI_PHUC'',''GYM'',0,90),(''COMBO_HOI_PHUC'',''SAUNA'',120,45),
(''COMBO_THU_GIAN'',''SAUNA'',0,45),(''COMBO_THU_GIAN'',''MASSAGE'',60,60),
(''COMBO_BINH_MINH'',''YOGA'',0,60),(''COMBO_BINH_MINH'',''POOL'',90,120),
(''COMBO_TRON_VEN'',''SAUNA'',0,45),(''COMBO_TRON_VEN'',''MASSAGE'',60,60),
(''COMBO_TRON_VEN'',''POOL'',120,120)
)v(combo,component,offset_minutes,duration)
JOIN dbo.Dining_Services c ON c.service_code=v.combo
JOIN @new n ON n.service_id=c.service_id
JOIN dbo.Dining_Services p ON p.service_code=v.component;

INSERT dbo.Dining_Slots(service_id,start_time)
SELECT s.service_id,CONVERT(TIME(0),v.start_time)
FROM(VALUES
(''COMBO_NANG_DONG'',''08:00''),(''COMBO_NANG_DONG'',''14:00''),
(''COMBO_HOI_PHUC'',''08:00''),(''COMBO_HOI_PHUC'',''14:00''),
(''COMBO_THU_GIAN'',''09:00''),(''COMBO_THU_GIAN'',''14:00''),
(''COMBO_THU_GIAN'',''15:00''),(''COMBO_BINH_MINH'',''06:30''),
(''COMBO_TRON_VEN'',''14:00'')
)v(code,start_time)
JOIN dbo.Dining_Services s ON s.service_code=v.code
JOIN @new n ON n.service_id=s.service_id
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.Dining_Slots t
 WHERE t.service_id=s.service_id AND t.start_time=CONVERT(TIME(0),v.start_time)
);
';

EXEC sys.sp_executesql N'
CREATE OR ALTER FUNCTION dbo.ServiceResourceUsage()
RETURNS TABLE
AS RETURN(
 SELECT a.reservation_id,a.service_id,a.visit_at,a.duration_minutes,a.guests
 FROM dbo.Dining_ServiceAllocations a
 JOIN dbo.Dining_Reservations r ON r.reservation_id=a.reservation_id
 LEFT JOIN dbo.Dining_ServicePayments p ON p.reservation_id=r.reservation_id
 WHERE r.status=''CONFIRMED''
 OR(r.status=''PENDING'' AND p.payment_status IN(''WAITING'',''REPORTED'')
    AND p.hold_until_utc>SYSUTCDATETIME())
 UNION ALL
 SELECT r.reservation_id,r.service_id,r.visit_at,
  COALESCE(p.duration_minutes,i.duration_minutes),r.guests
 FROM dbo.Dining_Reservations r
 JOIN dbo.Dining_ServiceInventory i ON i.service_id=r.service_id
 LEFT JOIN dbo.Dining_ServicePayments p ON p.reservation_id=r.reservation_id
 WHERE NOT EXISTS(
  SELECT 1 FROM dbo.Dining_ServiceAllocations a
  WHERE a.reservation_id=r.reservation_id
 )
 AND NOT EXISTS(
  SELECT 1 FROM dbo.Dining_Combos c WHERE c.service_id=r.service_id
 )
 AND(
  r.status=''CONFIRMED''
  OR(r.status=''PENDING'' AND p.payment_status IN(''WAITING'',''REPORTED'')
     AND p.hold_until_utc>SYSUTCDATETIME())
 )
);
';

EXEC sys.sp_executesql N'
CREATE OR ALTER FUNCTION dbo.ServiceRemaining(
 @service_id INT,@start DATETIME2,@minutes INT,@except_id INT
)
RETURNS INT
AS
BEGIN
 DECLARE @available INT,@snapshot BIT=0;
 SELECT @available=i.capacity
 FROM dbo.Dining_ServiceInventory i
 JOIN dbo.Dining_Services s ON s.service_id=i.service_id
 WHERE i.service_id=@service_id AND i.enabled=1 AND s.enabled=1;
 IF @available IS NULL RETURN 0;
 DECLARE @needs TABLE(
  service_id INT PRIMARY KEY,visit_at DATETIME2,duration_minutes INT
 );
 IF @except_id>0 AND EXISTS(
  SELECT 1 FROM dbo.Dining_ServiceAllocations WHERE reservation_id=@except_id
 )
 BEGIN
  SET @snapshot=1;
  INSERT @needs SELECT service_id,visit_at,duration_minutes
  FROM dbo.Dining_ServiceAllocations WHERE reservation_id=@except_id;
 END
 ELSE IF EXISTS(
  SELECT 1 FROM dbo.Dining_Combos WHERE service_id=@service_id
 )
  INSERT @needs
  SELECT component_service_id,DATEADD(MINUTE,start_offset_minutes,@start),
   duration_minutes
  FROM dbo.Dining_ComboItems WHERE combo_service_id=@service_id;
 ELSE INSERT @needs VALUES(@service_id,@start,@minutes);

 IF NOT EXISTS(SELECT 1 FROM @needs) RETURN 0;
 IF EXISTS(
  SELECT 1 FROM @needs n
  LEFT JOIN dbo.Dining_ServiceInventory i ON i.service_id=n.service_id
  LEFT JOIN dbo.Dining_Services s ON s.service_id=n.service_id
  WHERE i.service_id IS NULL OR i.enabled=0 OR s.enabled=0
  OR EXISTS(
   SELECT 1 FROM dbo.Dining_Combos c WHERE c.service_id=n.service_id
  )
  OR(@snapshot=0 AND n.duration_minutes<i.duration_minutes)
  OR DATEADD(MINUTE,n.duration_minutes,n.visit_at)
      >DATEADD(MINUTE,@minutes,@start)
  OR NOT EXISTS(
   SELECT 1 FROM dbo.Dining_Slots t
   WHERE t.service_id=n.service_id AND t.enabled=1
   AND t.start_time=CONVERT(TIME(0),n.visit_at)
  )
 ) RETURN 0;

 DECLARE @minimum INT;
 SELECT @minimum=MIN(i.capacity-COALESCE(u.used,0))
 FROM @needs n
 JOIN dbo.Dining_ServiceInventory i ON i.service_id=n.service_id
 OUTER APPLY(
  SELECT SUM(b.guests) AS used
  FROM dbo.ServiceResourceUsage() b
  WHERE b.service_id=n.service_id AND b.reservation_id<>@except_id
  AND b.visit_at<DATEADD(MINUTE,n.duration_minutes,n.visit_at)
  AND DATEADD(MINUTE,b.duration_minutes,b.visit_at)>n.visit_at
 )u;
 IF @minimum IS NULL OR @minimum<0 RETURN 0;
 RETURN CASE WHEN @minimum<@available THEN @minimum ELSE @available END;
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER FUNCTION dbo.ServiceOccupied(
 @service_id INT,@start DATETIME2,@minutes INT,@except_id INT
)
RETURNS INT
AS
BEGIN
 DECLARE @capacity INT;
 SELECT @capacity=capacity FROM dbo.Dining_ServiceInventory
 WHERE service_id=@service_id;
 RETURN COALESCE(@capacity,0)
  -dbo.ServiceRemaining(@service_id,@start,@minutes,@except_id);
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.CreateServiceHold
 @token UNIQUEIDENTIFIER,@service_id INT,@slot_id INT,@visit_date DATE,
 @guests INT,@full_name NVARCHAR(150),@phone VARCHAR(20),
 @email NVARCHAR(255),@notes NVARCHAR(1000),
 @percent INT,@client_hash BINARY(32)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @percent IS NULL OR @percent NOT IN(30,100)
 OR @guests IS NULL OR @guests NOT BETWEEN 1 AND 20
 OR @client_hash IS NULL OR @token IS NULL OR @visit_date IS NULL
 OR LEN(LTRIM(RTRIM(COALESCE(@full_name,N''''))))<2
 OR @phone IS NULL OR LEN(@phone)<>10 OR @phone LIKE ''%[^0-9]%''
 OR LEFT(@phone,2) NOT IN(''03'',''05'',''07'',''08'',''09'')
  THROW 51000,N''Thông tin đặt dịch vụ không hợp lệ.'',1;

 BEGIN TRANSACTION;
 DECLARE @lock INT;
 EXEC @lock=sys.sp_getapplock
  @Resource=''DiningInventory'',@LockMode=''Exclusive'',
  @LockOwner=''Transaction'',@LockTimeout=5000;
 IF @lock<0 THROW 51000,N''Hệ thống đang bận, vui lòng thử lại.'',1;

 DECLARE @previous VARCHAR(24)=(
  SELECT public_code FROM dbo.Dining_Reservations WHERE request_token=@token
 );
 IF @previous IS NOT NULL
 BEGIN COMMIT; SELECT @previous AS Code; RETURN; END;

 DECLARE @price DECIMAL(18,2),@name NVARCHAR(150),@group VARCHAR(16),
  @capacity INT,@minutes INT,@time TIME(0),@visit DATETIME2,
  @now DATETIME2=SYSUTCDATETIME();

 SELECT @price=s.unit_price,@name=s.service_name,@group=s.service_group,
  @capacity=i.capacity,@minutes=i.duration_minutes,@time=t.start_time
 FROM dbo.Dining_Services s WITH(UPDLOCK,HOLDLOCK)
 JOIN dbo.Dining_ServiceInventory i WITH(UPDLOCK,HOLDLOCK)
  ON i.service_id=s.service_id
 JOIN dbo.Dining_Slots t
  ON t.service_id=s.service_id AND t.slot_id=@slot_id
 WHERE s.service_id=@service_id AND s.enabled=1 AND i.enabled=1
 AND t.enabled=1 AND s.pricing_mode=''PER_PERSON'' AND s.unit_price>0;

 IF @price IS NULL
  THROW 51000,N''Dịch vụ chưa nhận đặt có thanh toán trực tuyến.'',1;
 SET @visit=DATEADD(
  SECOND,DATEDIFF(SECOND,CONVERT(TIME,''00:00''),@time),
  CONVERT(DATETIME2,@visit_date)
 );
 IF @visit<DATEADD(MINUTE,30,DATEADD(HOUR,7,@now))
 OR @visit_date>CONVERT(DATE,DATEADD(DAY,90,DATEADD(HOUR,7,@now)))
  THROW 51000,N''Đặt trước ít nhất 30 phút và tối đa 90 ngày.'',1;

 IF EXISTS(
  SELECT 1 FROM dbo.Dining_Reservations r
  JOIN dbo.Dining_ServicePayments p ON p.reservation_id=r.reservation_id
  WHERE r.status=''PENDING'' AND p.payment_status IN(''WAITING'',''REPORTED'')
  AND p.hold_until_utc>@now AND r.phone=@phone
 )
  THROW 51000,N''Số điện thoại này đang có lịch chờ thanh toán. Hãy hoàn tất hoặc hủy lịch đó trước.'',1;

 IF(
  SELECT COUNT(*) FROM dbo.Dining_ServicePayments
  WHERE client_hash=@client_hash
  AND created_at_utc>DATEADD(MINUTE,-30,@now)
 )>=5
  THROW 51000,N''Bạn đã tạo nhiều lịch liên tiếp. Vui lòng thử lại sau 30 phút.'',1;

 IF(
  SELECT COUNT(*) FROM dbo.Dining_ServicePayments p
  JOIN dbo.Dining_Reservations r ON r.reservation_id=p.reservation_id
  WHERE p.client_hash=@client_hash AND r.status=''PENDING''
  AND p.payment_status IN(''WAITING'',''REPORTED'') AND p.hold_until_utc>@now
 )>=2
  THROW 51000,N''Vui lòng hoàn tất hoặc hủy lịch đang chờ thanh toán trước.'',1;

 IF dbo.ServiceOccupied(@service_id,@visit,@minutes,0)+@guests>@capacity
  THROW 51000,N''Khung giờ này không còn đủ chỗ. Vui lòng chọn giờ hoặc số người khác.'',1;

 DECLARE @code VARCHAR(24)=
  CASE WHEN @group=''WELLNESS'' THEN ''DV-'' ELSE ''AT-'' END
  +UPPER(LEFT(REPLACE(CONVERT(VARCHAR(36),NEWID()),''-'',''''),16));
 DECLARE @total DECIMAL(18,2)=@price*@guests;

 INSERT dbo.Dining_Reservations(
  public_code,request_token,service_id,slot_id,service_group,service_name,
  visit_at,guests,pricing_mode,unit_price,estimated_total,
  full_name,phone,email,notes
 )
 VALUES(
  @code,@token,@service_id,@slot_id,@group,@name,@visit,@guests,
  ''PER_PERSON'',@price,@total,@full_name,@phone,@email,@notes
 );

 DECLARE @id INT=CONVERT(INT,SCOPE_IDENTITY());
 INSERT dbo.Dining_ServicePayments(
  reservation_id,payment_percent,total_amount,required_amount,
  duration_minutes,hold_until_utc,client_hash
 )
 VALUES(
  @id,@percent,@total,CEILING(@total*@percent/100),@minutes,
  DATEADD(MINUTE,10,@now),@client_hash
 );

 IF EXISTS(SELECT 1 FROM dbo.Dining_Combos WHERE service_id=@service_id)
 BEGIN
  INSERT dbo.Dining_ServiceAllocations(
   reservation_id,service_id,service_name,visit_at,duration_minutes,guests
  )
  SELECT @id,c.component_service_id,s.service_name,
   DATEADD(MINUTE,c.start_offset_minutes,@visit),c.duration_minutes,@guests
  FROM dbo.Dining_ComboItems c
  JOIN dbo.Dining_Services s ON s.service_id=c.component_service_id
  WHERE c.combo_service_id=@service_id;

  DECLARE @itinerary NVARCHAR(MAX);
  SELECT @itinerary=STUFF((
   SELECT N''; ''+a.service_name+N'' ''
    +CONVERT(NVARCHAR(5),a.visit_at,108)+N''–''
    +CONVERT(NVARCHAR(5),DATEADD(MINUTE,a.duration_minutes,a.visit_at),108)
   FROM dbo.Dining_ServiceAllocations a WHERE a.reservation_id=@id
   ORDER BY a.visit_at,a.service_id
   FOR XML PATH(''''),TYPE
  ).value(''.'',''nvarchar(max)''),1,2,N'''');

  UPDATE dbo.Dining_ServicePayments
  SET staff_note=LEFT(N''Lịch sử dụng combo: ''+@itinerary,1000)
  WHERE reservation_id=@id;
 END
 ELSE
  INSERT dbo.Dining_ServiceAllocations(
   reservation_id,service_id,service_name,visit_at,duration_minutes,guests
  )
  VALUES(@id,@service_id,@name,@visit,@minutes,@guests);

 COMMIT;
 SELECT @code AS Code;
END;
';

-- =========================================================
-- 5. THANH TOÁN / HỦY / HOÀN TẤT DỊCH VỤ
-- =========================================================

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.RequestServiceCancellation
 @code VARCHAR(24),@reason NVARCHAR(500)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF LEN(LTRIM(RTRIM(COALESCE(@reason,N'''')))) NOT BETWEEN 3 AND 500
  THROW 51000,N''Nhập lý do hủy từ 3 đến 500 ký tự.'',1;
 BEGIN TRANSACTION;
 DECLARE @lock INT;
 EXEC @lock=sys.sp_getapplock
  @Resource=''DiningInventory'',@LockMode=''Exclusive'',
  @LockOwner=''Transaction'',@LockTimeout=5000;
 IF @lock<0 THROW 51000,N''Hệ thống đang bận.'',1;
 DECLARE @id INT,@paid DECIMAL(18,2),@status VARCHAR(16),
  @visit DATETIME2,@payment VARCHAR(20);
 SELECT @id=r.reservation_id,@paid=p.paid_amount,@status=r.status,
  @visit=r.visit_at,@payment=p.payment_status
 FROM dbo.Dining_Reservations r
 JOIN dbo.Dining_ServicePayments p ON p.reservation_id=r.reservation_id
 WHERE r.public_code=@code;
 IF @id IS NULL OR @status NOT IN(''PENDING'',''CONFIRMED'')
 OR @visit<=DATEADD(HOUR,7,SYSUTCDATETIME())
  THROW 51000,N''Lịch không còn được gửi yêu cầu hủy trên web.'',1;
 UPDATE dbo.Dining_Reservations
 SET cancellation_reason=@reason,updated_at_utc=SYSUTCDATETIME(),
  status=CASE WHEN @paid=0 THEN ''CANCELLED'' ELSE status END,
  cancelled_at_utc=CASE WHEN @paid=0 THEN SYSUTCDATETIME() ELSE NULL END
 WHERE reservation_id=@id;
 UPDATE dbo.Dining_ServicePayments
 SET cancel_requested_at_utc=SYSUTCDATETIME(),
  payment_status=CASE WHEN @paid>0 THEN ''REFUND_REVIEW''
   WHEN @payment=''REPORTED'' THEN ''REVIEW'' ELSE payment_status END,
  hold_until_utc=CASE WHEN @paid=0 THEN SYSUTCDATETIME() ELSE hold_until_utc END
 WHERE reservation_id=@id;
 COMMIT;
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.ReviewServiceCancellation
 @code VARCHAR(24),@approve BIT,@note NVARCHAR(1000)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @approve IS NULL OR NULLIF(LTRIM(RTRIM(@note)),N'''') IS NULL
  THROW 51000,N''Nhập quyết định và ghi chú xử lý.'',1;
 BEGIN TRANSACTION;
 DECLARE @lock INT;
 EXEC @lock=sys.sp_getapplock
  @Resource=''DiningInventory'',@LockMode=''Exclusive'',
  @LockOwner=''Transaction'',@LockTimeout=5000;
 IF @lock<0 THROW 51000,N''Hệ thống đang bận.'',1;
 DECLARE @id INT=(
  SELECT r.reservation_id FROM dbo.Dining_Reservations r
  JOIN dbo.Dining_ServicePayments p ON p.reservation_id=r.reservation_id
  WHERE r.public_code=@code AND r.status IN(''PENDING'',''CONFIRMED'')
  AND p.cancel_requested_at_utc IS NOT NULL
 );
 IF @id IS NULL THROW 51000,N''Không có yêu cầu hủy đang chờ xét.'',1;
 UPDATE dbo.Dining_ServicePayments
 SET staff_note=@note,
  cancel_requested_at_utc=CASE WHEN @approve=0
   THEN NULL ELSE cancel_requested_at_utc END,
  payment_status=CASE WHEN @approve=1 THEN ''REFUND_REVIEW''
   WHEN(SELECT status FROM dbo.Dining_Reservations WHERE reservation_id=@id)
    <>''CONFIRMED'' THEN ''REVIEW''
   WHEN paid_amount>=total_amount THEN ''PAID''
   WHEN paid_amount>=required_amount THEN ''DEPOSIT_PAID'' ELSE ''REVIEW'' END
 WHERE reservation_id=@id;
 IF @approve=1
  UPDATE dbo.Dining_Reservations
  SET status=''CANCELLED'',cancelled_at_utc=SYSUTCDATETIME(),
   updated_at_utc=SYSUTCDATETIME()
  WHERE reservation_id=@id;
 COMMIT;
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.ConfirmServiceBankRefund
 @code VARCHAR(24),@bank_reference VARCHAR(100),@amount DECIMAL(18,2)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF NULLIF(LTRIM(RTRIM(@bank_reference)),'''') IS NULL
 OR @amount IS NULL OR @amount<=0
  THROW 51000,N''Nhập mã giao dịch hoàn và số tiền thực hoàn.'',1;
 BEGIN TRANSACTION;
 DECLARE @lock INT;
 EXEC @lock=sys.sp_getapplock
  @Resource=''DiningInventory'',@LockMode=''Exclusive'',
  @LockOwner=''Transaction'',@LockTimeout=5000;
 IF @lock<0 THROW 51000,N''Hệ thống đang bận.'',1;
 DECLARE @id INT,@paid DECIMAL(18,2),@refunded DECIMAL(18,2);
 SELECT @id=r.reservation_id,@paid=p.paid_amount,@refunded=p.refunded_amount
 FROM dbo.Dining_Reservations r
 JOIN dbo.Dining_ServicePayments p ON p.reservation_id=r.reservation_id
 WHERE r.public_code=@code AND r.status=''CANCELLED'';
 IF @id IS NULL
  THROW 51000,N''Chỉ ghi nhận hoàn tiền cho đơn đã hủy.'',1;
 IF EXISTS(
  SELECT 1 FROM dbo.Dining_ServiceRefunds WHERE bank_reference=@bank_reference
 )
 BEGIN
  IF NOT EXISTS(
   SELECT 1 FROM dbo.Dining_ServiceRefunds
   WHERE bank_reference=@bank_reference AND reservation_id=@id AND amount=@amount
  )
   THROW 51000,N''Mã giao dịch hoàn đã dùng cho khoản khác.'',1;
  COMMIT; RETURN;
 END;
 IF @refunded+@amount>@paid
  THROW 51000,N''Tổng tiền hoàn vượt số tiền đã nhận.'',1;
 INSERT dbo.Dining_ServiceRefunds(reservation_id,bank_reference,amount)
 VALUES(@id,@bank_reference,@amount);
 UPDATE dbo.Dining_ServicePayments
 SET refunded_amount=@refunded+@amount,
  payment_status=CASE WHEN @refunded+@amount=@paid
   THEN ''REFUNDED'' ELSE ''PART_REFUND'' END
 WHERE reservation_id=@id;
 COMMIT;
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.ReportServiceTransfer @code VARCHAR(24)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRANSACTION;
 DECLARE @lock INT;
 EXEC @lock=sys.sp_getapplock
  @Resource=''DiningInventory'',@LockMode=''Exclusive'',
  @LockOwner=''Transaction'',@LockTimeout=5000;
 IF @lock<0 THROW 51000,N''Hệ thống đang bận.'',1;
 UPDATE p SET payment_status=''REPORTED''
 FROM dbo.Dining_ServicePayments p
 JOIN dbo.Dining_Reservations r ON r.reservation_id=p.reservation_id
 WHERE r.public_code=@code AND r.status=''PENDING'' AND p.paid_amount=0
 AND p.payment_status IN(''WAITING'',''REPORTED'')
 AND p.hold_until_utc>SYSUTCDATETIME()
 AND p.cancel_requested_at_utc IS NULL;
 IF @@ROWCOUNT<>1
  THROW 51000,N''Lịch đã hết hạn giữ chỗ hoặc được xử lý. Nếu đã chuyển tiền, hãy liên hệ khách sạn để đối soát.'',1;
 COMMIT;
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.CompletePaidService @code VARCHAR(24)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRANSACTION;
 DECLARE @lock INT;
 EXEC @lock=sys.sp_getapplock
  @Resource=''DiningInventory'',@LockMode=''Exclusive'',
  @LockOwner=''Transaction'',@LockTimeout=5000;
 IF @lock<0 THROW 51000,N''Hệ thống đang bận.'',1;
 UPDATE r SET status=''COMPLETED'',updated_at_utc=SYSUTCDATETIME()
 FROM dbo.Dining_Reservations r
 JOIN dbo.Dining_ServicePayments p ON p.reservation_id=r.reservation_id
 WHERE r.public_code=@code AND r.status=''CONFIRMED''
 AND p.paid_amount=p.total_amount AND p.refunded_amount=0
 AND p.cancel_requested_at_utc IS NULL
 AND DATEADD(MINUTE,p.duration_minutes,r.visit_at)
  <=DATEADD(HOUR,7,SYSUTCDATETIME());
 IF @@ROWCOUNT<>1
  THROW 51000,N''Chỉ hoàn tất sau giờ kết thúc, đã thu đủ tiền và không có yêu cầu hủy.'',1;
 COMMIT;
END;
';

-- =========================================================
-- 6. GIÁ VÀ LỊCH DỊCH VỤ KHÁCH LƯU TRÚ
-- =========================================================

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Dining_ResidentRules'',N''U'') IS NULL
CREATE TABLE dbo.Dining_ResidentRules(
 service_id INT NOT NULL PRIMARY KEY REFERENCES dbo.Dining_Services(service_id),
 is_free BIT NOT NULL,
 discount_percent DECIMAL(5,2) NOT NULL
  CHECK(discount_percent BETWEEN 0 AND 100)
);
IF OBJECT_ID(N''dbo.Dining_ResidentReservations'',N''U'') IS NULL
CREATE TABLE dbo.Dining_ResidentReservations(
 reservation_id INT NOT NULL PRIMARY KEY
  REFERENCES dbo.Dining_Reservations(reservation_id),
 booking_id INT NOT NULL REFERENCES dbo.Bookings(booking_id),
 created_at_utc DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
INSERT dbo.Dining_ResidentRules(service_id,is_free,discount_percent)
SELECT s.service_id,v.is_free,v.percent_value
FROM(VALUES
(''POOL'',1,0),(''GYM'',1,0),
(''MASSAGE'',0,20),(''SAUNA'',0,20),(''YOGA'',0,20)
)v(code,is_free,percent_value)
JOIN dbo.Dining_Services s ON s.service_code=v.code
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.Dining_ResidentRules r WHERE r.service_id=s.service_id
);
IF(
 SELECT COUNT(*) FROM dbo.Dining_ResidentRules r
 JOIN dbo.Dining_Services s ON s.service_id=r.service_id
 WHERE s.service_code IN(''POOL'',''GYM'',''MASSAGE'',''SAUNA'',''YOGA'')
)<>5
 THROW 51000,N''Thiếu dịch vụ lẻ để cấu hình giá khách lưu trú.'',1;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER FUNCTION dbo.ResidentServicePrice(@service_id INT)
RETURNS DECIMAL(18,2)
AS
BEGIN
 DECLARE @price DECIMAL(18,2);
 IF EXISTS(SELECT 1 FROM dbo.Dining_Combos WHERE service_id=@service_id)
 BEGIN
  IF NOT EXISTS(
   SELECT 1 FROM dbo.Dining_ComboItems WHERE combo_service_id=@service_id
  ) RETURN NULL;
  IF EXISTS(
   SELECT 1 FROM dbo.Dining_ComboItems c
   LEFT JOIN dbo.Dining_ServiceInventory i ON i.service_id=c.component_service_id
   WHERE c.combo_service_id=@service_id
   AND(i.service_id IS NULL OR c.duration_minutes<>i.duration_minutes)
  ) RETURN NULL;
  IF EXISTS(
   SELECT 1 FROM dbo.Dining_ComboItems c
   LEFT JOIN dbo.Dining_ResidentRules p ON p.service_id=c.component_service_id
   JOIN dbo.Dining_Services s ON s.service_id=c.component_service_id
   WHERE c.combo_service_id=@service_id
   AND(p.service_id IS NULL OR s.unit_price IS NULL
       OR s.pricing_mode<>''PER_PERSON'')
  ) RETURN NULL;
  SELECT @price=SUM(
   CASE WHEN p.is_free=1 THEN CONVERT(DECIMAL(18,2),0)
   ELSE ROUND(s.unit_price*(100-p.discount_percent)/100,0) END
  )
  FROM dbo.Dining_ComboItems c
  JOIN dbo.Dining_ResidentRules p ON p.service_id=c.component_service_id
  JOIN dbo.Dining_Services s ON s.service_id=c.component_service_id
  WHERE c.combo_service_id=@service_id;
 END
 ELSE
  SELECT @price=CASE WHEN p.is_free=1 THEN 0
   ELSE ROUND(s.unit_price*(100-p.discount_percent)/100,0) END
  FROM dbo.Dining_ResidentRules p
  JOIN dbo.Dining_Services s ON s.service_id=p.service_id
  WHERE p.service_id=@service_id AND s.pricing_mode=''PER_PERSON''
  AND s.unit_price IS NOT NULL;
 RETURN @price;
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER FUNCTION dbo.ResidentBookingEligible(@booking_id INT)
RETURNS BIT
AS
BEGIN
 DECLARE @eligible BIT=0;
 SELECT @eligible=1
 FROM dbo.Bookings b
 JOIN dbo.Booking_Payments p ON p.booking_id=b.booking_id
 WHERE b.booking_id=@booking_id
 AND b.trang_thai IN(N''Đã xác nhận'',N''Đã nhận phòng'')
 AND COALESCE(b.so_nguoi_lon,0)>=1 AND COALESCE(b.so_tre_em,0)>=0
 AND p.payment_status=''PAID'' AND p.is_demo=0 AND p.amount_paid>0
 AND p.cancellation_status IN(''NONE'',''DENIED'')
 AND b.ngay_checkin IS NOT NULL AND b.ngay_checkout>b.ngay_checkin
 AND DATEADD(HOUR,12,CONVERT(DATETIME2,b.ngay_checkout))
  >DATEADD(HOUR,7,SYSUTCDATETIME());
 RETURN @eligible;
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER FUNCTION dbo.ResidentScheduleFits(@reservation_id INT)
RETURNS BIT
AS
BEGIN
 DECLARE @booking INT,@guests INT,@limit INT,
  @checkin DATETIME2,@checkout DATETIME2;
 SELECT @booking=l.booking_id,@guests=r.guests,
  @limit=COALESCE(b.so_nguoi_lon,1)+COALESCE(b.so_tre_em,0),
  @checkin=DATEADD(HOUR,14,CONVERT(DATETIME2,b.ngay_checkin)),
  @checkout=DATEADD(HOUR,12,CONVERT(DATETIME2,b.ngay_checkout))
 FROM dbo.Dining_ResidentReservations l
 JOIN dbo.Dining_Reservations r ON r.reservation_id=l.reservation_id
 JOIN dbo.Bookings b ON b.booking_id=l.booking_id
 WHERE l.reservation_id=@reservation_id;
 IF @booking IS NULL RETURN 1;
 IF @guests>@limit OR NOT EXISTS(
  SELECT 1 FROM dbo.Dining_ServiceAllocations WHERE reservation_id=@reservation_id
 ) RETURN 0;
 IF EXISTS(
  SELECT 1 FROM dbo.Dining_ServiceAllocations a
  WHERE a.reservation_id=@reservation_id
  AND(a.visit_at<@checkin
      OR DATEADD(MINUTE,a.duration_minutes,a.visit_at)>@checkout)
 ) RETURN 0;
 IF EXISTS(
  SELECT 1 FROM dbo.Dining_ServiceAllocations n
  CROSS APPLY(
   SELECT n.visit_at AS point_at
   UNION
   SELECT a.visit_at FROM dbo.Dining_ServiceAllocations a
   JOIN dbo.Dining_ResidentReservations l ON l.reservation_id=a.reservation_id
   WHERE l.booking_id=@booking AND a.reservation_id<>@reservation_id
   AND a.visit_at>=n.visit_at
   AND a.visit_at<DATEADD(MINUTE,n.duration_minutes,n.visit_at)
  )e
  WHERE n.reservation_id=@reservation_id
  AND COALESCE((
   SELECT SUM(a.guests)
   FROM dbo.Dining_ServiceAllocations a
   JOIN dbo.Dining_ResidentReservations l ON l.reservation_id=a.reservation_id
   JOIN dbo.Dining_Reservations r ON r.reservation_id=a.reservation_id
   LEFT JOIN dbo.Dining_ServicePayments p ON p.reservation_id=r.reservation_id
   WHERE l.booking_id=@booking AND a.reservation_id<>@reservation_id
   AND a.visit_at<=e.point_at
   AND DATEADD(MINUTE,a.duration_minutes,a.visit_at)>e.point_at
   AND(
    r.status=''CONFIRMED''
    OR(r.status=''PENDING'' AND p.payment_status IN(''WAITING'',''REPORTED'')
       AND p.hold_until_utc>SYSUTCDATETIME())
   )
  ),0)+@guests>@limit
 ) RETURN 0;
 RETURN 1;
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.CreateResidentServiceHold
 @booking_id INT,@token UNIQUEIDENTIFIER,@service_id INT,@slot_id INT,
 @visit_date DATE,@guests INT,@percent INT
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @token IS NULL OR @visit_date IS NULL
 OR @guests IS NULL OR @guests NOT BETWEEN 1 AND 20
 OR @percent IS NULL OR @percent NOT IN(30,100)
  THROW 51000,N''Thông tin đặt dịch vụ không hợp lệ.'',1;

 BEGIN TRANSACTION;
 DECLARE @owner INT,@max_guests INT,@checkin DATETIME2,@checkout DATETIME2,
  @name NVARCHAR(150),@phone VARCHAR(20),@email NVARCHAR(255);
 SELECT @owner=b.booking_id,
  @max_guests=COALESCE(b.so_nguoi_lon,1)+COALESCE(b.so_tre_em,0),
  @checkin=DATEADD(HOUR,14,CONVERT(DATETIME2,b.ngay_checkin)),
  @checkout=DATEADD(HOUR,12,CONVERT(DATETIME2,b.ngay_checkout)),
  @name=u.ho_ten,@phone=u.so_dien_thoai,@email=u.email
 FROM dbo.Bookings b WITH(UPDLOCK,HOLDLOCK)
 JOIN dbo.Users u ON u.user_id=b.user_id
 WHERE b.booking_id=@booking_id;

 IF @owner IS NULL OR dbo.ResidentBookingEligible(@booking_id)=0
  THROW 51000,N''Ưu đãi chỉ áp dụng khi đơn phòng đã xác nhận, đã đối soát tiền và còn trong thời gian lưu trú.'',1;
 IF @guests>@max_guests
  THROW 51000,N''Số người dùng dịch vụ vượt số khách của đơn phòng.'',1;

 DECLARE @lock INT;
 EXEC @lock=sys.sp_getapplock
  @Resource=''DiningInventory'',@LockMode=''Exclusive'',
  @LockOwner=''Transaction'',@LockTimeout=5000;
 IF @lock<0 THROW 51000,N''Hệ thống đang bận. Vui lòng thử lại.'',1;

 DECLARE @previous VARCHAR(24);
 SELECT @previous=r.public_code
 FROM dbo.Dining_Reservations r
 JOIN dbo.Dining_ResidentReservations l ON l.reservation_id=r.reservation_id
 WHERE r.request_token=@token AND l.booking_id=@booking_id;
 IF @previous IS NOT NULL
 BEGIN COMMIT; SELECT @previous AS Code; RETURN; END;

 IF EXISTS(SELECT 1 FROM dbo.Dining_Reservations WHERE request_token=@token)
  THROW 51000,N''Phiên đặt dịch vụ không hợp lệ.'',1;
 IF(
  SELECT COUNT(*) FROM dbo.Dining_ResidentReservations
  WHERE booking_id=@booking_id
  AND created_at_utc>DATEADD(MINUTE,-30,SYSUTCDATETIME())
 )>=5
  THROW 51000,N''Bạn đã tạo nhiều lịch liên tiếp. Vui lòng thử lại sau 30 phút.'',1;
 IF EXISTS(
  SELECT 1 FROM dbo.Dining_ResidentReservations l
  JOIN dbo.Dining_Reservations r ON r.reservation_id=l.reservation_id
  JOIN dbo.Dining_ServicePayments p ON p.reservation_id=r.reservation_id
  WHERE l.booking_id=@booking_id AND r.status=''PENDING''
  AND p.payment_status IN(''WAITING'',''REPORTED'')
  AND p.hold_until_utc>SYSUTCDATETIME()
 )
  THROW 51000,N''Hãy thanh toán hoặc hủy lịch dịch vụ đang chờ trước khi đặt thêm.'',1;

 DECLARE @price DECIMAL(18,2),@service_name NVARCHAR(150),
  @duration INT,@time TIME(0),@visit DATETIME2;
 SELECT @price=dbo.ResidentServicePrice(s.service_id),
  @service_name=s.service_name,@duration=i.duration_minutes,@time=t.start_time
 FROM dbo.Dining_Services s
 JOIN dbo.Dining_ServiceInventory i ON i.service_id=s.service_id
 JOIN dbo.Dining_Slots t
  ON t.service_id=s.service_id AND t.slot_id=@slot_id
 WHERE s.service_id=@service_id AND s.service_group=''WELLNESS''
 AND s.enabled=1 AND i.enabled=1 AND t.enabled=1;

 IF @price IS NULL OR @duration IS NULL OR @price<0
  THROW 51000,N''Dịch vụ chưa áp dụng giá khách lưu trú.'',1;
 SET @visit=DATEADD(
  SECOND,DATEDIFF(SECOND,CONVERT(TIME,''00:00''),@time),
  CONVERT(DATETIME2,@visit_date)
 );
 IF @visit<@checkin OR DATEADD(MINUTE,@duration,@visit)>@checkout
 OR @visit<DATEADD(MINUTE,30,DATEADD(HOUR,7,SYSUTCDATETIME()))
  THROW 51000,N''Lịch phải từ 14:00 ngày nhận phòng đến 12:00 ngày trả phòng và đặt trước ít nhất 30 phút.'',1;
 IF dbo.ServiceRemaining(@service_id,@visit,@duration,0)<@guests
  THROW 51000,N''Khung giờ không còn đủ chỗ. Hãy chọn giờ hoặc số người khác.'',1;

 DECLARE @needs TABLE(
  service_id INT PRIMARY KEY,visit_at DATETIME2,duration_minutes INT
 );
 IF EXISTS(SELECT 1 FROM dbo.Dining_Combos WHERE service_id=@service_id)
  INSERT @needs
  SELECT component_service_id,DATEADD(MINUTE,start_offset_minutes,@visit),
   duration_minutes
  FROM dbo.Dining_ComboItems WHERE combo_service_id=@service_id;
 ELSE INSERT @needs VALUES(@service_id,@visit,@duration);

 IF EXISTS(
  SELECT 1 FROM @needs a JOIN @needs b ON a.service_id<b.service_id
  AND a.visit_at<DATEADD(MINUTE,b.duration_minutes,b.visit_at)
  AND b.visit_at<DATEADD(MINUTE,a.duration_minutes,a.visit_at)
 )
  THROW 51000,N''Lịch combo bị chồng giờ, cần khách sạn kiểm tra cấu hình.'',1;

 DECLARE @code VARCHAR(24)=
  CASE WHEN @price=0 THEN ''RS-'' ELSE ''DV-'' END
  +UPPER(LEFT(REPLACE(CONVERT(VARCHAR(36),NEWID()),''-'',''''),16));
 DECLARE @total DECIMAL(18,2)=@price*@guests;

 INSERT dbo.Dining_Reservations(
  public_code,request_token,service_id,slot_id,service_group,service_name,
  visit_at,guests,pricing_mode,unit_price,estimated_total,
  full_name,phone,email,status
 )
 VALUES(
  @code,@token,@service_id,@slot_id,''WELLNESS'',@service_name,
  @visit,@guests,''PER_PERSON'',@price,@total,
  COALESCE(@name,N''Khách lưu trú''),COALESCE(@phone,''''),@email,
  CASE WHEN @price=0 THEN ''CONFIRMED'' ELSE ''PENDING'' END
 );
 DECLARE @id INT=CONVERT(INT,SCOPE_IDENTITY());

 INSERT dbo.Dining_ResidentReservations(reservation_id,booking_id)
 VALUES(@id,@booking_id);
 INSERT dbo.Dining_ServiceAllocations(
  reservation_id,service_id,service_name,visit_at,duration_minutes,guests
 )
 SELECT @id,n.service_id,s.service_name,n.visit_at,n.duration_minutes,@guests
 FROM @needs n JOIN dbo.Dining_Services s ON s.service_id=n.service_id;

 DECLARE @itinerary NVARCHAR(MAX);
 SELECT @itinerary=STUFF((
  SELECT N''; ''+a.service_name+N'' ''
   +CONVERT(NVARCHAR(5),a.visit_at,108)+N''–''
   +CONVERT(NVARCHAR(5),DATEADD(MINUTE,a.duration_minutes,a.visit_at),108)
  FROM dbo.Dining_ServiceAllocations a WHERE a.reservation_id=@id
  ORDER BY a.visit_at,a.service_id
  FOR XML PATH(''''),TYPE
 ).value(''.'',''nvarchar(max)''),1,2,N'''');

 IF @price>0
  INSERT dbo.Dining_ServicePayments(
   reservation_id,payment_percent,total_amount,required_amount,
   duration_minutes,hold_until_utc,client_hash,staff_note
  )
  VALUES(
   @id,@percent,@total,CEILING(@total*@percent/100),
   @duration,DATEADD(MINUTE,10,SYSUTCDATETIME()),
   HASHBYTES(''SHA2_256'',CONVERT(VARCHAR(20),@booking_id)),
   LEFT(N''Giá khách lưu trú. Lịch: ''+@itinerary,1000)
  );
 ELSE
  UPDATE dbo.Dining_Reservations
  SET staff_note=LEFT(N''Miễn phí theo đơn phòng. Lịch: ''+@itinerary,1000)
  WHERE reservation_id=@id;

 IF dbo.ResidentScheduleFits(@id)=0
  THROW 51000,N''Lịch trùng hoạt động khác hoặc vượt số khách của đơn phòng.'',1;
 COMMIT;
 SELECT @code AS Code;
END;
';

-- Nhân viên đối soát tiền dịch vụ thực nhận.
EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.ConfirmServiceBankPayment
 @code VARCHAR(24),@bank_reference VARCHAR(100),@amount DECIMAL(18,2)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF NULLIF(LTRIM(RTRIM(@bank_reference)),'''') IS NULL
 OR @amount IS NULL OR @amount<=0
  THROW 51000,N''Phải nhập mã giao dịch ngân hàng và số tiền thực nhận.'',1;

 BEGIN TRANSACTION;
 DECLARE @resident_booking_id INT,@resident_ok BIT=1,@locked_booking INT;
 SELECT @resident_booking_id=l.booking_id
 FROM dbo.Dining_ResidentReservations l
 JOIN dbo.Dining_Reservations r ON r.reservation_id=l.reservation_id
 WHERE r.public_code=@code;
 IF @resident_booking_id IS NOT NULL
 BEGIN
  SELECT @locked_booking=booking_id
  FROM dbo.Bookings WITH(UPDLOCK,HOLDLOCK)
  WHERE booking_id=@resident_booking_id;
  SET @resident_ok=dbo.ResidentBookingEligible(@resident_booking_id);
 END;

 DECLARE @lock INT;
 EXEC @lock=sys.sp_getapplock
  @Resource=''DiningInventory'',@LockMode=''Exclusive'',
  @LockOwner=''Transaction'',@LockTimeout=5000;
 IF @lock<0 THROW 51000,N''Hệ thống đang bận.'',1;

 DECLARE @id INT,@service INT,@visit DATETIME2,
  @guests INT,@duration INT,@status VARCHAR(16),
  @total DECIMAL(18,2),@required DECIMAL(18,2),
  @paid DECIMAL(18,2),@capacity INT,
  @existing_payment VARCHAR(20),@cancel_requested DATETIME2;

 SELECT @id=r.reservation_id,@service=r.service_id,
  @visit=r.visit_at,@guests=r.guests,@duration=p.duration_minutes,
  @status=r.status,@total=p.total_amount,@required=p.required_amount,
  @existing_payment=p.payment_status,
  @cancel_requested=p.cancel_requested_at_utc
 FROM dbo.Dining_Reservations r
 JOIN dbo.Dining_ServicePayments p ON p.reservation_id=r.reservation_id
 WHERE r.public_code=@code;

 IF @id IS NULL
  THROW 51000,N''Không tìm thấy đơn dịch vụ có thanh toán.'',1;

 IF EXISTS(
  SELECT 1 FROM dbo.Dining_ServiceTransfers WHERE bank_reference=@bank_reference
 )
 BEGIN
  IF NOT EXISTS(
   SELECT 1 FROM dbo.Dining_ServiceTransfers
   WHERE bank_reference=@bank_reference AND reservation_id=@id AND amount=@amount
  )
   THROW 51000,N''Mã giao dịch đã dùng cho khoản tiền hoặc đơn khác.'',1;
  IF NOT(
   @existing_payment=''REVIEW''
   AND @status IN(''PENDING'',''CONFIRMED'')
   AND @cancel_requested IS NULL
  )
  BEGIN COMMIT; RETURN; END;
 END
 ELSE
  INSERT dbo.Dining_ServiceTransfers(reservation_id,bank_reference,amount)
  VALUES(@id,@bank_reference,@amount);

 SELECT @paid=SUM(amount) FROM dbo.Dining_ServiceTransfers WHERE reservation_id=@id;
 SELECT @capacity=i.capacity
 FROM dbo.Dining_ServiceInventory i
 JOIN dbo.Dining_Services s ON s.service_id=i.service_id
 WHERE i.service_id=@service AND i.enabled=1 AND s.enabled=1;

 DECLARE @can_confirm BIT=CASE
 WHEN @cancel_requested IS NULL AND @paid BETWEEN @required AND @total
 AND(
  @status=''CONFIRMED''
  OR(
   @status=''PENDING'' AND @resident_ok=1
   AND dbo.ResidentScheduleFits(@id)=1
   AND @visit>DATEADD(HOUR,7,SYSUTCDATETIME())
   AND @capacity IS NOT NULL
   AND dbo.ServiceOccupied(@service,@visit,@duration,@id)+@guests<=@capacity
  )
 ) THEN 1 ELSE 0 END;

 UPDATE dbo.Dining_ServicePayments
 SET paid_amount=@paid,
  payment_status=CASE
   WHEN cancel_requested_at_utc IS NOT NULL THEN ''REFUND_REVIEW''
   WHEN @can_confirm=0 THEN ''REVIEW''
   WHEN @paid=@total THEN ''PAID'' ELSE ''DEPOSIT_PAID'' END,
  hold_until_utc=CASE WHEN @can_confirm=0
   THEN SYSUTCDATETIME() ELSE hold_until_utc END
 WHERE reservation_id=@id;
 IF @can_confirm=1
  UPDATE dbo.Dining_Reservations
  SET status=''CONFIRMED'',updated_at_utc=SYSUTCDATETIME()
  WHERE reservation_id=@id;
 COMMIT;
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER TRIGGER dbo.TR_ResidentRoomChanges
ON dbo.Bookings AFTER UPDATE
AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(
  SELECT 1 FROM inserted i JOIN deleted d ON d.booking_id=i.booking_id
  WHERE(
   ISNULL(i.ngay_checkin,''19000101'')<>ISNULL(d.ngay_checkin,''19000101'')
   OR ISNULL(i.ngay_checkout,''19000101'')<>ISNULL(d.ngay_checkout,''19000101'')
   OR ISNULL(i.so_nguoi_lon,0)<>ISNULL(d.so_nguoi_lon,0)
   OR ISNULL(i.so_tre_em,0)<>ISNULL(d.so_tre_em,0)
   OR ISNULL(i.user_id,0)<>ISNULL(d.user_id,0)
  )
  AND EXISTS(
   SELECT 1 FROM dbo.Dining_ResidentReservations l
   JOIN dbo.Dining_Reservations r ON r.reservation_id=l.reservation_id
   WHERE l.booking_id=i.booking_id AND r.status IN(''PENDING'',''CONFIRMED'')
  )
 )
  THROW 51000,N''Đơn đang có lịch dịch vụ. Cần xử lý các lịch trước khi đổi ngày hoặc số khách phòng.'',1;

 IF NOT EXISTS(
  SELECT 1 FROM inserted i JOIN deleted d ON d.booking_id=i.booking_id
  WHERE i.trang_thai=N''Đã hủy'' AND ISNULL(d.trang_thai,N'''')<>N''Đã hủy''
 ) RETURN;

 DECLARE @lock INT;
 EXEC @lock=sys.sp_getapplock
  @Resource=''DiningInventory'',@LockMode=''Exclusive'',
  @LockOwner=''Transaction'',@LockTimeout=5000;
 IF @lock<0
  THROW 51000,N''Chưa thể hủy lịch dịch vụ đi kèm. Vui lòng thử lại.'',1;

 DECLARE @cancelled TABLE(reservation_id INT PRIMARY KEY);
 UPDATE r
 SET status=''CANCELLED'',cancelled_at_utc=SYSUTCDATETIME(),
  updated_at_utc=SYSUTCDATETIME(),
  cancellation_reason=N''Đơn phòng đã hủy; ngừng quyền sử dụng ưu đãi lưu trú.''
 OUTPUT inserted.reservation_id INTO @cancelled
 FROM dbo.Dining_Reservations r
 JOIN dbo.Dining_ResidentReservations l ON l.reservation_id=r.reservation_id
 JOIN inserted i ON i.booking_id=l.booking_id
 JOIN deleted d ON d.booking_id=i.booking_id
 WHERE i.trang_thai=N''Đã hủy''
 AND ISNULL(d.trang_thai,N'''')<>N''Đã hủy''
 AND r.status IN(''PENDING'',''CONFIRMED'')
 AND r.visit_at>DATEADD(HOUR,7,SYSUTCDATETIME());

 UPDATE p
 SET cancel_requested_at_utc=SYSUTCDATETIME(),
  hold_until_utc=SYSUTCDATETIME(),
  payment_status=CASE WHEN p.paid_amount>0 THEN ''REFUND_REVIEW''
   WHEN p.payment_status=''REPORTED'' THEN ''REVIEW'' ELSE p.payment_status END
 FROM dbo.Dining_ServicePayments p
 JOIN @cancelled c ON c.reservation_id=p.reservation_id;
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.CancelResidentFreeService
 @booking_id INT,@code VARCHAR(24),@reason NVARCHAR(500)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF LEN(LTRIM(RTRIM(COALESCE(@reason,N'''')))) NOT BETWEEN 3 AND 500
  THROW 51000,N''Nhập lý do từ 3 đến 500 ký tự.'',1;
 BEGIN TRANSACTION;
 DECLARE @lock INT;
 EXEC @lock=sys.sp_getapplock
  @Resource=''DiningInventory'',@LockMode=''Exclusive'',
  @LockOwner=''Transaction'',@LockTimeout=5000;
 IF @lock<0 THROW 51000,N''Hệ thống đang bận.'',1;
 UPDATE r
 SET status=''CANCELLED'',cancelled_at_utc=SYSUTCDATETIME(),
  updated_at_utc=SYSUTCDATETIME(),cancellation_reason=@reason
 FROM dbo.Dining_Reservations r
 JOIN dbo.Dining_ResidentReservations l ON l.reservation_id=r.reservation_id
 WHERE l.booking_id=@booking_id AND r.public_code=@code
 AND r.unit_price=0 AND r.status=''CONFIRMED''
 AND r.visit_at>DATEADD(HOUR,7,SYSUTCDATETIME());
 IF @@ROWCOUNT<>1
  THROW 51000,N''Lịch không còn được hủy trực tuyến.'',1;
 COMMIT;
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.CompleteResidentFreeService @code VARCHAR(24)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRANSACTION;
 DECLARE @lock INT;
 EXEC @lock=sys.sp_getapplock
  @Resource=''DiningInventory'',@LockMode=''Exclusive'',
  @LockOwner=''Transaction'',@LockTimeout=5000;
 IF @lock<0 THROW 51000,N''Hệ thống đang bận.'',1;
 UPDATE r SET status=''COMPLETED'',updated_at_utc=SYSUTCDATETIME()
 FROM dbo.Dining_Reservations r
 JOIN dbo.Dining_ResidentReservations l ON l.reservation_id=r.reservation_id
 WHERE r.public_code=@code AND r.unit_price=0 AND r.status=''CONFIRMED''
 AND EXISTS(
  SELECT 1 FROM dbo.Dining_ServiceAllocations a
  WHERE a.reservation_id=r.reservation_id
 )
 AND NOT EXISTS(
  SELECT 1 FROM dbo.Dining_ServiceAllocations a
  WHERE a.reservation_id=r.reservation_id
  AND DATEADD(MINUTE,a.duration_minutes,a.visit_at)
   >DATEADD(HOUR,7,SYSUTCDATETIME())
 );
 IF @@ROWCOUNT<>1
  THROW 51000,N''Chỉ hoàn tất sau khi kết thúc lịch miễn phí.'',1;
 COMMIT;
END;
';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.SetDiningReservationStatus
 @public_code VARCHAR(24),@status VARCHAR(16),
 @note NVARCHAR(1000)=NULL,@unit_price DECIMAL(18,2)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRANSACTION;
 DECLARE @lock INT;
 EXEC @lock=sys.sp_getapplock
  @Resource=''DiningInventory'',@LockMode=''Exclusive'',
  @LockOwner=''Transaction'',@LockTimeout=5000;
 IF @lock<0 THROW 51000,N''Hệ thống đang bận.'',1;

 IF UPPER(LTRIM(RTRIM(@status))) IN(''CONFIRMED'',''COMPLETED'')
 AND EXISTS(
  SELECT 1 FROM dbo.Dining_Reservations r
  JOIN dbo.Dining_ResidentReservations l ON l.reservation_id=r.reservation_id
  WHERE r.public_code=UPPER(LTRIM(RTRIM(@public_code)))
 )
  THROW 51000,N''Dịch vụ lưu trú phải dùng luồng đặt/hoàn tất riêng để kiểm tra đơn phòng và giờ kết thúc.'',1;

 IF UPPER(LTRIM(RTRIM(@status))) IN(''CONFIRMED'',''COMPLETED'')
 AND EXISTS(
  SELECT 1 FROM dbo.Dining_Reservations r
  JOIN dbo.Dining_Combos c ON c.service_id=r.service_id
  WHERE r.public_code=UPPER(LTRIM(RTRIM(@public_code)))
 )
  THROW 51000,N''Combo phải đi qua luồng giữ chỗ/thanh toán và lịch dịch vụ con.'',1;

 IF EXISTS(
  SELECT 1 FROM dbo.Dining_Reservations r
  JOIN dbo.Dining_ServicePayments p ON p.reservation_id=r.reservation_id
  WHERE r.public_code=UPPER(LTRIM(RTRIM(@public_code)))
 )
  THROW 51000,N''Đơn này phải xử lý qua thủ tục thanh toán/hủy dịch vụ; không xác nhận bằng luồng cũ.'',1;

 IF UPPER(LTRIM(RTRIM(@status)))=''CONFIRMED''
 AND EXISTS(
  SELECT 1 FROM dbo.Dining_Reservations r
  JOIN dbo.Dining_ServiceInventory i ON i.service_id=r.service_id
  WHERE r.public_code=UPPER(LTRIM(RTRIM(@public_code)))
  AND dbo.ServiceOccupied(
   r.service_id,r.visit_at,i.duration_minutes,r.reservation_id
  )+r.guests>i.capacity
 )
  THROW 51000,N''Khung giờ không còn đủ chỗ để xác nhận yêu cầu cũ.'',1;

 EXEC dbo.SetDiningReservationStatus_Legacy
  @public_code,@status,@note,@unit_price;
 COMMIT;
END;
';

-- =========================================================
-- 7. COMBO ĂN UỐNG VÀ ẢNH MỚI NHẤT
-- =========================================================

-- CẤU HÌNH MẪU: nhà hàng 40 chỗ, thời gian dùng bàn 90 phút.
-- Combo và đặt bàn thường dùng chung chỗ.
EXEC sys.sp_executesql N'
DECLARE @seeds TABLE(
 code VARCHAR(30) PRIMARY KEY,name NVARCHAR(150),
 description NVARCHAR(800),price DECIMAL(18,2),
 resource_code VARCHAR(30),image_url NVARCHAR(1000)
);
INSERT @seeds VALUES
(
 ''COMBO_COM_VIET'',N''Combo Cơm Việt — bữa trưa'',
 N''Suất ăn gồm salad rau, gà nướng sả, cá kho tộ, canh rau, cơm trắng, trái cây và trà đá. Phục vụ bữa trưa; thời gian dùng bữa 90 phút. Giá trọn gói theo người, số suất bằng số người đặt; đã gồm thuế và phí phục vụ. Món và đồ uống gọi thêm tính riêng. Có thể chứa cá, đậu nành và lạc; hãy liên hệ nhà hàng trước khi thanh toán nếu có dị ứng.'',
 249000,''LUNCH'',
 N''https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=1000&q=85''
),
(
 ''COMBO_CHAY'',N''Combo Chay thanh đạm — bữa trưa'',
 N''Suất chay gồm salad rau củ, đậu hũ sốt nấm, rau củ xào, canh nấm, cơm trắng, trái cây và trà thảo mộc. Phục vụ bữa trưa; thời gian dùng bữa 90 phút. Giá trọn gói theo người, số suất bằng số người đặt; đã gồm thuế và phí phục vụ. Món và đồ uống gọi thêm tính riêng. Có đậu nành; bếp dùng chung, hãy liên hệ trước nếu có dị ứng hoặc yêu cầu ăn chay đặc biệt.'',
 219000,''LUNCH'',
 N''https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=1000&q=85''
),
(
 ''COMBO_HAI_SAN'',N''Combo Hải sản — bữa tối'',
 N''Suất ăn gồm súp bắp hải sản, tôm nướng, mực xào rau củ, cơm chiên hải sản, chè dừa và một ly trà chanh. Phục vụ bữa tối; thời gian dùng bữa 90 phút. Giá trọn gói theo người, số suất bằng số người đặt; đã gồm thuế và phí phục vụ. Món và đồ uống gọi thêm tính riêng. Có hải sản, trứng và đậu nành; hãy liên hệ nhà hàng trước khi thanh toán nếu có dị ứng.'',
 399000,''DINNER'',
 N''https://www.thucphamsachhd.com/uploads/files/2025/03/23/20190622053808361264hai-san.max-800x800-847.jpg''
),
(
 ''COMBO_SET_AU'',N''Combo Beefsteak — bữa tối'',
 N''Suất ăn gồm súp bí đỏ, bò bít tết với khoai tây nghiền, salad xanh, panna cotta và một ly mocktail không cồn. Phục vụ bữa tối; thời gian dùng bữa 90 phút. Giá trọn gói theo người, số suất bằng số người đặt; đã gồm thuế và phí phục vụ. Món và đồ uống gọi thêm tính riêng. Có sữa và có thể chứa lúa mì; hãy liên hệ trước nếu có dị ứng. Yêu cầu độ chín thịt trong phần ghi chú.'',
 449000,''DINNER'',
 N''https://raw.githubusercontent.com/bedimcode/responsive-steakhouse-website/c5dcaa094bb4bc0c9bf088d52708585f87ace86a/assets/img/menu-dish-2.png''
);

IF(
 SELECT COUNT(*) FROM dbo.Dining_Services
 WHERE service_code IN(''LUNCH'',''DINNER'') AND service_group=''DINING''
)<>2
 THROW 51000,N''Thiếu dịch vụ đặt bàn ăn trưa/ăn tối.'',1;

IF EXISTS(
 SELECT 1 FROM @seeds v JOIN dbo.Dining_Services s ON s.service_code=v.code
 WHERE s.service_group<>''DINING'' OR NOT EXISTS(
  SELECT 1 FROM dbo.Dining_Combos c WHERE c.service_id=s.service_id
 )
)
 THROW 51000,N''Mã combo đã được dùng bởi dữ liệu khác. Cần kiểm tra trước khi chạy.'',1;

INSERT dbo.Dining_ServiceInventory(
 service_id,capacity,duration_minutes,is_sample
)
SELECT service_id,40,90,1 FROM dbo.Dining_Services s
WHERE s.service_code IN(''LUNCH'',''DINNER'')
AND NOT EXISTS(
 SELECT 1 FROM dbo.Dining_ServiceInventory i WHERE i.service_id=s.service_id
);

IF EXISTS(
 SELECT 1 FROM dbo.Dining_Services s
 JOIN dbo.Dining_Combos c ON c.service_id=s.service_id
 WHERE s.service_code IN(''LUNCH'',''DINNER'')
)
 THROW 51000,N''LUNCH/DINNER phải là dịch vụ lẻ, không được là combo.'',1;

IF EXISTS(
 SELECT 1 FROM dbo.Dining_Services s
 WHERE s.service_code IN(''LUNCH'',''DINNER'')
 AND NOT EXISTS(
  SELECT 1 FROM dbo.Dining_Slots t WHERE t.service_id=s.service_id AND t.enabled=1
 )
)
 THROW 51000,N''Phải cấu hình giờ ăn trưa và ăn tối trước.'',1;

DECLARE @new TABLE(service_id INT PRIMARY KEY);
INSERT dbo.Dining_Services(
 service_code,service_group,service_name,description,
 pricing_mode,unit_price,image_url
)
OUTPUT inserted.service_id INTO @new
SELECT v.code,''DINING'',v.name,v.description,''PER_PERSON'',v.price,v.image_url
FROM @seeds v
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.Dining_Services s WHERE s.service_code=v.code
);

INSERT dbo.Dining_Combos(service_id,is_sample)
SELECT service_id,1 FROM @new;

INSERT dbo.Dining_ServiceInventory(
 service_id,capacity,duration_minutes,is_sample
)
SELECT n.service_id,20,i.duration_minutes,1
FROM @new n JOIN dbo.Dining_Services s ON s.service_id=n.service_id
JOIN @seeds v ON v.code=s.service_code
JOIN dbo.Dining_Services p ON p.service_code=v.resource_code
JOIN dbo.Dining_ServiceInventory i ON i.service_id=p.service_id;

INSERT dbo.Dining_ComboItems(
 combo_service_id,component_service_id,start_offset_minutes,duration_minutes
)
SELECT n.service_id,p.service_id,0,i.duration_minutes
FROM @new n JOIN dbo.Dining_Services s ON s.service_id=n.service_id
JOIN @seeds v ON v.code=s.service_code
JOIN dbo.Dining_Services p ON p.service_code=v.resource_code
JOIN dbo.Dining_ServiceInventory i ON i.service_id=p.service_id;

INSERT dbo.Dining_Slots(service_id,start_time)
SELECT n.service_id,t.start_time
FROM @new n JOIN dbo.Dining_Services s ON s.service_id=n.service_id
JOIN @seeds v ON v.code=s.service_code
JOIN dbo.Dining_Services p ON p.service_code=v.resource_code
JOIN dbo.Dining_Slots t ON t.service_id=p.service_id AND t.enabled=1;
';

-- Cập nhật cả combo Beefsteak đã tồn tại từ trước.
EXEC sys.sp_executesql N'
UPDATE dbo.Dining_Services
SET service_name=N''Combo Beefsteak — bữa tối'',
 description=N''Suất Beefsteak gồm súp bí đỏ, bò bít tết ăn kèm khoai tây nghiền và rau củ nướng, salad xanh, panna cotta và một ly mocktail không cồn. Phục vụ bữa tối; thời gian dùng bữa 90 phút. Giá trọn gói theo người, số suất bằng số người đặt; đã gồm thuế và phí phục vụ. Món và đồ uống gọi thêm tính riêng. Có sữa và có thể chứa lúa mì; hãy liên hệ trước nếu có dị ứng. Yêu cầu độ chín thịt trong phần ghi chú.'',
 image_url=N''https://raw.githubusercontent.com/bedimcode/responsive-steakhouse-website/c5dcaa094bb4bc0c9bf088d52708585f87ace86a/assets/img/menu-dish-2.png''
WHERE service_code=''COMBO_SET_AU'' AND service_group=''DINING'';
';

-- Ảnh riêng cho từng combo thư giãn.
EXEC sys.sp_executesql N'
UPDATE s SET image_url=v.image_url
FROM dbo.Dining_Services s
JOIN(VALUES
(''COMBO_NANG_DONG'',
 N''https://images.unsplash.com/photo-1575429198097-0414ec08e8cd?auto=format&fit=crop&w=1000&q=85''),
(''COMBO_HOI_PHUC'',
 N''https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?auto=format&fit=crop&w=1000&q=85''),
(''COMBO_THU_GIAN'',
 N''https://images.unsplash.com/photo-1600334129128-685c5582fd35?auto=format&fit=crop&w=1000&q=85''),
(''COMBO_BINH_MINH'',
 N''https://images.unsplash.com/photo-1506126613408-eca07ce68773?auto=format&fit=crop&w=1000&q=85''),
(''COMBO_TRON_VEN'',
 N''https://images.unsplash.com/photo-1540541338287-41700207dee6?auto=format&fit=crop&w=1000&q=85'')
)v(service_code,image_url) ON v.service_code=s.service_code;
';

-- Ảnh hải sản do bạn chọn.
EXEC sys.sp_executesql N'
UPDATE dbo.Dining_Services
SET image_url=N''https://www.thucphamsachhd.com/uploads/files/2025/03/23/20190622053808361264hai-san.max-800x800-847.jpg''
WHERE service_code=''COMBO_HAI_SAN'' AND service_group=''DINING'';
';

-- Đồng bộ trạng thái đơn theo tình trạng tiền đã lưu.
EXEC sys.sp_executesql N'
UPDATE b SET trang_thai=N''Chờ thanh toán''
FROM dbo.Bookings b
JOIN dbo.Booking_Payments p ON p.booking_id=b.booking_id
WHERE b.trang_thai=N''Đã xác nhận'' AND p.payment_method=''BANK''
AND p.payment_status IN(''UNPAID'',''PENDING'');

UPDATE b SET trang_thai=N''Đã xác nhận''
FROM dbo.Bookings b
JOIN dbo.Booking_Payments p ON p.booking_id=b.booking_id
WHERE b.trang_thai IN(N''Chờ thanh toán'',N''Chờ đối soát'',N''Chờ xác nhận'')
AND p.payment_status=''PAID'';
';

COMMIT TRANSACTION;

PRINT N'Đã cập nhật bản gộp. Dữ liệu đơn và giao dịch hiện có được giữ lại.';

SELECT
 s.service_code,
 s.service_name,
 s.service_group,
 s.unit_price,
 dbo.ResidentServicePrice(s.service_id) AS resident_price
FROM dbo.Dining_Services s
ORDER BY s.service_group,s.service_id;

END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO